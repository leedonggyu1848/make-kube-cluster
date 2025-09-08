## 클러스터 생성

### 1. KVM 및 관련 패키지 설치

``` bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager -y
```

- `qemu-kvm`: 가상머신을 실행하는 핵심 패키지

- `libvirt-*`: 가상머신을 관리하고 제어하는 라이브러리 및 도구

- `bridge-utils`: 가상 네트워크를 설정하는 도구

- `virt-manager`: 가상머신을 쉽게 생성하고 관리할 수 있는 GUI(그래픽 인터페이스) 관리자

&nbsp;

#### 사용자 계정 권한 설정

가상머신을 `sudo` 명령어 없이 편리하게 관리하려면 현재 사용자를 `libvirt`와 `kvm` 그룹에 추가

``` bash
sudo adduser $USER libvirt
sudo adduser $USER kvm
```

권한 설정을 적용하려면 **시스템을 완전히 재부팅**하거나, 로그아웃 후 다시 로그인

&nbsp;

#### KVM 서비스 상태 확인

패키지 설치와 권한 설정이 완료되면, `libvirtd` 서비스가 잘 실행되고 있는지 확인

```bash
systemctl is-active libvirtd
```

&nbsp;

### 2. Terraform VM 생성하기

#### **필수 패키지 설치 및 GPG 키 추가**

먼저 Terraform 패키지 저장소를 신뢰하기 위한 GPG 키를 시스템에 추가한다

``` bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
```

#### **HashiCorp 저장소 추가**

GPG 키를 확인한 후, 시스템에 HashiCorp 공식 저장소를 추가

``` bash
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
```

#### **Terraform 설치**

이제 패키지 목록을 업데이트하고 Terraform을 설치

``` bash
sudo apt update
sudo apt install terraform -y
sudo apt install genisoimage
```

genisoimage는 테라폼에서 cloud-init iso 이미지를 생성하는 동안 mkisofs 명령어를 찾을 수 없을때 발생 추가로 설치해야한다

미리 정의된 테라폼을 이용할것 <a href="https://github.com/leedonggyu1848/make-kube-cluster" target="_blank">클론github</a>

 #### Terraform 실행

``` bash
#main.tf 가 존재하는 위치에서 실행한다
terraform init
terraform plan # 설정확인
terraform apply # 적용

terraform apply --var vm=4 # 가상머신 4개 생성 개수 변경 가능 기본값 3
```

**tf 파일 실행시 권한 오류 해결**

<a href="https://github.com/dmacvicar/terraform-provider-libvirt/issues/1163" target="_blank">해결 github</a>

<center><img src="https://image.minnnningnas.duckdns.org/images/20344d2b-bfbb-48b9-8aea-db2d50c5eee1.webp" style="zoom:50%;"></center>

위 권한 오류가 발생한다면 위 링크에 해결 방법이 있다

- 해당 파일 맨 아래줄을 확인  `/etc/apparmor.d/abstractions/libvirt-qemu`

  ```bash
  vi /etc/apparmor.d/abstractions/libvirt-qemu
  ```

  아래 명령어가 없다면 추가한다 (맨 아래에는 없고 맨아래 주석위에 존재했음)

  ```bash
    include if exists <abstractions/libvirt-qemu.d>
  ```

- 폴더가 없다면 생성 `/etc/apparmor.d/abstractions/libvirt-qemu.d`

  ```bash
  sudo mkdir -p /etc/apparmor.d/abstractions/libvirt-qemu.d
  ```

- 해당 위치에 파일 생성 `/etc/apparmor.d/abstractions/libvirt-qemu.d/override`.

  ```bash
  sudo vi /etc/apparmor.d/abstractions/libvirt-qemu.d/override
  ```

  ```bash
  # /etc/apparmor.d/abstractions/libvirt-qemu.d/override
  
   /var/lib/libvirt/images/** rwk,
  ```

- 재시작 `AppAmor`

  ```bash
  sudo systemctl restart apparmor
  ```

위 명령어를 실행하면 정삭적으로 실행된다

&nbsp;

**libvirt에 'default' 정의 안됨 오류**

- **현재 스토리지 풀 확인**

  먼저 현재 시스템에 어떤 스토리지 풀이 있는지 확인

  ``` bash
  virsh pool-list --all
  ```

  아마 이 명령어의 결과가 비어 있거나, 'default' 풀이 `inactive` 상태 비활성화 상태면 바로 활성화 단계로 이동

- 풀이 없다면 생성한다

  ``` bash
  virsh pool-define-as default dir --target /var/lib/libvirt/images
  ```

- 풀 빌드

  ``` bash
   virsh pool-build default
  ```

- 풀 활성화

  ``` bash
  # 풀을 활성화(시작)합니다.
  sudo virsh pool-start default
  
  # 시스템 재부팅 시 풀이 자동으로 시작되도록 설정합니다. (매우 중요)
  sudo virsh pool-autostart default
  ```

&nbsp;

### 3. Ansible로 환경 구축

먼저 파이썬을 설치해야한다 파이썬 가상환경에서 Ansible을 사용하는 이유는 프로젝트를 진행하다 보면 각기 다른 버전의 Ansible이나 관련 라이브러리가 필요한 경우가 생기는데


   * A 프로젝트: Ansible 2.9 버전과 특정 라이브러리 v1.0이 필요
   * B 프로젝트: Ansible 2.12 버전과 동일 라이브러리 v2.0이 필요

가상환경(venv)은 이런 문제를 해결 할 수 있다

&nbsp;

#### 파이썬 설치와 가상환경 실행

``` bash
sudo apt update
sudo apt install python3-pip python3-venv -y
```

이후 playbook이 있는 프로젝트 폴더로 이동

``` bash
python3 -m venv .venv # 가상환경 생성
source .venv/bin/activate # 가상환경 활성화
```

#### Ansible 설치

Ansible은 Python 기반이므로, Python과 패키지 관리자인 pip가 설치되어 있어야 한다

``` bash
pip3 install ansible
ansible --version #설치확인
```

#### Ansible 연결 테스트

플레이북을 실행하기 전에, Ansible이 모든 VM에 정상적으로 접속할 수 있는지 확인할 수 있다 ping 모듈을 사용하면 간단하게 테스트한다

``` bash
ansible all -i inventory.ini -m ping
```

* `all`: inventory.ini에 있는 모든 호스트를 대상
* `-i inventory.ini`: 사용할 인벤토리 파일을 지정
* `-m ping`: ping 모듈을 사용 (ICMP ping이 아닌, SSH 접속 후 간단한 스크립트를 실행하여 응답을 확인하는 방식)

<center><img src="https://image.minnnningnas.duckdns.org/images/e19a048d-1035-421f-a86c-2133828e8c3e.webp" style="zoom:50%;"></center>

#### Ansible 실행

``` bash
make all
```

&nbsp;

### 4. 클러스터 확인

- **마스터 노드에 SSH로 접속**

  ``` bash
  ssh ubuntu@192.168.100.100 -i ~/.ssh/vm_ssh_key
  ```

  테라폼에서 ssh키를 따로 생성해서 `~/.ssh/vm_ssh_key`에 위치한다

  (IP 주소는 inventory.ini에 지정한 마스터 노드 IP)

- **마스터 노드 터미널에서 `kubectl` 명령어로 노드 상태를 확인**

  ``` bash
  kubectl get nodes -o wide
  ```

<center><img src="https://image.minnnningnas.duckdns.org/images/a347a995-2d7e-4066-aa0a-e8e98e79e6a8.webp" style="zoom:50%;"></center>

# AWS를 이용한 클러스터

variables.tfvars 파일에 들어가야 하는 값
```
aws_access_key = "aws_access_key"
aws_secret_key = "aws_secret_key"
vm = 3
```
테라폼으로 aws ec2생성 시작
```bash
terraform apply -var-file -var-file variables.tfvars
```
