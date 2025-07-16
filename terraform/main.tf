# main.tf

# user variable 

variable "vm" {
  description = "생성할 vm 개수"
  type = number
  default=3
}

# Terraform 설정 블록: 필요한 프로바이더와 버전을 명시합니다.
terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt" # libvirt 프로바이더의 올바른 소스
      version = "0.8.3" # 프로바이더 버전. 최신 안정 버전을 사용하거나 특정 버전을 지정할 수 있습니다.
    }
  }
}

# 1. libvirt 프로바이더 설정
# libvirt 데몬에 연결하기 위한 URI를 지정합니다.
# 일반적으로 'qemu:///system'은 시스템 전체 libvirt 데몬에 연결합니다.
provider "libvirt" {
  uri = "qemu:///system"
}

# 2. 내부 네트워크 정의
# 4개의 VM이 통신할 수 있는 격리된 내부 네트워크를 생성합니다.
resource "libvirt_network" "internal_vm_network" {
  name      = "internal-vm-network"
  mode      = "nat" # NAT 모드로 설정하여 호스트를 통해 외부 인터넷 접근 가능
  domain    = "internal.local" # 내부 DNS 도메인
  addresses = ["192.168.100.0/24"] # 내부 네트워크 대역
  autostart = true # 호스트 부팅 시 자동 시작

  dhcp {
    enabled  = false
  }
}

# 3. 기본 Ubuntu 클라우드 이미지 다운로드 (볼륨 정의)
# 이 리소스는 Ubuntu Noble (24.04 LTS) 서버 클라우드 이미지를 다운로드하여
# libvirt의 'default' 스토리지 풀에 저장합니다.
# 'source' URL은 최신 버전으로 변경될 수 있으니, 필요에 따라 확인하세요.
resource "libvirt_volume" "ubuntu_base_image" {
  name   = "ubuntu-noble-server-cloudimg-amd64.qcow2" # 일관된 이름
  source = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" # 최신 Noble LTS 이미지
  format = "qcow2"
  pool   = "default" # 'default'라는 이름의 스토리지 풀이 존재한다고 가정합니다.
}

# 4. VM용 디스크 볼륨 생성 (기본 이미지 복제) - 각 VM마다 생성
resource "libvirt_volume" "ubuntu_vm_disk" {
  count          = var.vm # VM 디스크 생성 개수
  name           = "ubuntu-vm-${count.index + 1}-disk.qcow2" # 각 VM마다 고유한 디스크 이름
  base_volume_id = libvirt_volume.ubuntu_base_image.id
  size           = 20 * 1024 * 1024 * 1024 # 20 GB (바이트 단위)
  format         = "qcow2"
  pool           = "default"
}

# 5. Cloud-init 디스크 생성 - 각 VM마다 생성
resource "libvirt_cloudinit_disk" "ubuntu_cloudinit" {
  count = var.vm # cloud-init 디스크 생성 개수
  name  = "ubuntu-cloudinit-${count.index + 1}.iso" # 각 VM마다 고유한 cloud-init 디스크 이름
  pool  = "default"
  # user_data는 YAML 형식의 cloud-config 스크립트입니다.
  user_data = <<-EOF
#cloud-config
hostname: ubuntu-vm-${count.index + 1} # 각 VM마다 고유한 호스트 이름
ssh_pwauth: false
manage_etc_hosts: localhost
users:
  - name: ubuntu
    groups: sudo
    sudo: "ALL=(ALL) NOPASSWD: ALL"
    shell: /bin/bash
    ssh_authorized_keys:
      - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5J0GbyxlESF37LB2F1IZAmqmee1UyQnJV2dIch0qd98JmjaD2bjhkpgDc8EzopaC2Ah1aprdMQfNScPJe95AoUeQwQVvRplsUaMwOkp3zHgH8QbG3Yl2yu/AavDvQ4nSPHEeLr5Ahd3yql28cPBZWORvZFekn4X/+m68vSu3EmVoNvxM9s35VZHjWON6OVFs4C8VTOL3nactk/y35xq4XzoBZ/5lGFvSNri2RxPtuGdj/GpSyoo8yRC/6UzkMDRXweDvmvNkgVsLIMR4SDuW9MirQMzX3D2nuMXkd1kG3FmzPCiPCKI2njrEnjixusMEXop4XOdQ9S6R9HyUWAx4/biGVZ/fPDiLgPxrom6vTl6Cwrn40RqRsuUa3IGJ19uKnvimhASHuSvvvlrSiF1UFYtFhon453b4CnR5NAkDOpIDVsnoPULU0AOm0VG2tNYiNTsjE20lQhxUEMawsRQA1emf9rdJ4VSuV8R1Bcw6aaQ2gkR7TUJS0Yvj+tJ2rQWuoeiKros4AhHi2tldGz2ZsNuyJPVT4MKBbTlEGKMtvqQj6Rcz+Bkp4UygWC/qsRetUtgqKvX5GoWJljNttlawMJ5p7U3M0oWxfvaDYFO3hD7v/SqNFhiNv6bK2ZJaSXX7cn+PFKiCh/RRDNmrCQU6jLje7ZlmEfCNrtsZUqTQbRQ== one@one-pc"
chpasswd:
    users:
        - {name: root, password: pw, type: text}
    expire: false
  EOF
}

# 6. 가상 머신 (도메인) 정의 - 4개 생성
resource "libvirt_domain" "ubuntu_vm" {
  count  = var.vm # VM 생성 개수
  name   = "ubuntu-vm-${count.index + 1}" # 각 VM마다 고유한 이름 (ubuntu-vm-1, ubuntu-vm-2 등)
  memory = 2048 # MB
  vcpu   = 2

  # 위에서 생성한 cloud-init 디스크를 VM에 연결합니다.
  cloudinit = libvirt_cloudinit_disk.ubuntu_cloudinit[count.index].id

  # 네트워크 인터페이스 설정 - 새로 정의한 내부 네트워크에 연결
  network_interface {
    network_id = libvirt_network.internal_vm_network.id # 내부 네트워크 ID 사용
    addresses = ["192.168.100.${count.index + 100}"]
  }

  # 디스크 연결
  disk {
    volume_id = libvirt_volume.ubuntu_vm_disk[count.index].id
  }

  # 그래픽 설정 (선택 사항: VNC 또는 SPICE를 통해 VM 콘솔에 접근)
  graphics {
    type        = "spice" # SPICE 또는 "vnc"
    listen_type = "address"
    autoport    = true # 사용 가능한 포트를 자동으로 할당합니다.
  }

  # 콘솔 설정 (선택 사항: virsh console 명령으로 VM에 접속)
  console {
    type        = "pty"
    target_type = "serial"
    target_port = 0
  }

  # QEMU 게스트 에이전트 활성화 (선택 사항)
  # VM 내부에 'qemu-guest-agent' 패키지가 설치되어 있어야 합니다.
  # 이를 통해 호스트와 게스트 간의 더 나은 통신 및 정보 교환이 가능합니다.
  # qemu_agent_enabled = true
}
