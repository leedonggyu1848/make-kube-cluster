# Terraform configuration file
# VM을 '--var vm=3"과 같이 인자로 받은 수만큼 생성합니다.
# ~/.ssh/vm_ssh_key와 ~/.ssh/vm_ssh_key.pub를 생성합니다.
# ../inventory.ini 파일을 생성하여 ansible이 어떻게 vm에 접속해야 하는지 알려줍니다.

# 사용자 정의 변수
variable "vm" {
  description   = "The number of virtual machine to create"
  type          = number
  default       = 3
}

# 필요한 프로바이더와 버전을 명시
terraform {
  required_providers {

    # libvirt - vm 만드는데 필요
    libvirt = {
      source    = "dmacvicar/libvirt"
      version   = "0.8.3"
    }

    # local - local file만드는데 필요
    local = {
      source    = "hashicorp/local"
      version   = "2.5.3"
    }

    # tls - ssh key 만드는데 필요
    tls = {
      source    = "hashicorp/tls"
      version   = "4.1.0"
    }
  }
}

# libvirt 프로바이더 설정
# 'qemu:///system'은 시스템 전체 libvirt 데몬에 연결
provider "libvirt" {
  uri = "qemu:///system"
}

# ssh key쌍 생성
resource "tls_private_key" "vm_ssh_key" {
  algorithm   = "RSA"
  rsa_bits    = 4096
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.vm_ssh_key.private_key_pem
  filename        = pathexpand("~/.ssh/vm_ssh_key")
  file_permission = "0600"
}

resource "local_file" "ssh_public_key" {
  content         = tls_private_key.vm_ssh_key.public_key_openssh
  filename        = pathexpand("~/.ssh/vm_ssh_key.pub")
  file_permission = "0644"
}

# 내부 네트워크 정의
resource "libvirt_network" "internal_vm_network" {
  name      = "internal-vm-network"
  mode      = "nat"
  domain    = "internal.local"
  addresses = ["192.168.100.0/24"]
  autostart = true # 호스트 부팅 시 자동 시작

  dhcp {
    enabled = false
  }
}

# 기본 Ubuntu 클라우드 이미지 다운로드 (볼륨 정의)
# 이 리소스는 Ubuntu Noble 서버 클라우드 이미지를 다운로드하여
# libvirt의 'default' 스토리지 풀에 저장
# TODO: 만약 default가 없다면 직접 만드는 로직을 추가하면 더 좋을듯
resource "libvirt_volume" "ubuntu_base_image" {
  name   = "ubuntu-noble-server-cloudimg-amd64.qcow2"
  source = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  format = "qcow2"
  pool   = "default" # [!] default'라는 이름의 스토리지 풀이 존재한다고 가정
}

# VM용 디스크 볼륨 생성 (기본 이미지 복제) - 각 VM마다 생성
resource "libvirt_volume" "ubuntu_vm_disk" {
  count          = var.vm
  name           = "ubuntu-vm-${count.index + 1}-disk.qcow2" # 각 VM마다 고유한 디스크 이름
  base_volume_id = libvirt_volume.ubuntu_base_image.id
  size           = 20 * 1024 * 1024 * 1024 # 20 GB
  format         = "qcow2"
  pool           = "default"
}

# Cloud-init 디스크 생성 - 각 VM마다 생성
resource "libvirt_cloudinit_disk" "ubuntu_cloudinit" {
  count     = var.vm
  name      = "ubuntu-cloudinit-${count.index + 1}.iso"
  pool      = "default"
  user_data = <<-EOF
#cloud-config
hostname: ubuntu-vm-${count.index + 1}
ssh_pwauth: false
manage_etc_hosts: true
users:
  - name: ubuntu
    groups: sudo
    sudo: "ALL=(ALL) NOPASSWD: ALL"
    shell: /bin/bash
    ssh_authorized_keys:
      - "${tls_private_key.vm_ssh_key.public_key_openssh}"
chpasswd:
    users:
        - {name: root, password: pw, type: text}
    expire: false
  EOF

  provisioner "local-exec" {
      when        = destroy
      command     = "ssh-keygen -f '${pathexpand("~/.ssh/known_hosts")}' -R '192.168.100.${100 + count.index}'"
      on_failure  = continue
  }
}

resource "local_file" "inventory" {
  filename        = "${path.module}/../inventory.ini"
  file_permission = "0666"
  content         = <<EOF
[masters]
master-node ansible_host=192.168.100.100
  
[workers]
${join("\n", [for i in range(var.vm - 1) : "worker-node${i + 1} ansible_host=192.168.100.${101 + i}"])}

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${pathexpand("~/.ssh/vm_ssh_key")}
EOF
}

# 가상 머신 (도메인) 정의
resource "libvirt_domain" "ubuntu_vm" {
  count         = var.vm
  name          = "ubuntu-vm-${count.index + 1}"
  memory        = 2048 # MB
  vcpu          = 2
  cloudinit     = libvirt_cloudinit_disk.ubuntu_cloudinit[count.index].id
  network_interface {
    network_id  = libvirt_network.internal_vm_network.id
    addresses   = ["192.168.100.${count.index + 100}"]
  }
  disk {
    volume_id   = libvirt_volume.ubuntu_vm_disk[count.index].id
  }
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  # 콘솔 설정 (virsh console 명령으로 VM에 접속)
  console {
    type        = "pty"
    target_type = "serial"
    target_port = 0
  }
}
