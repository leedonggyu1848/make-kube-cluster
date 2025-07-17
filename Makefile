
.PHONY: all update_apt install_tools configure_firewall init_master join_workers install_flannel

ANSIBLE_INVENTORY = ./inventory.ini

all: update_apt install_tools configure_firewall init_master join_workers install_flannel

update_apt:
	ansible-playbook -i $(ANSIBLE_INVENTORY) playbook/update_apt.yml

install_tools:
	ansible-playbook -i $(ANSIBLE_INVENTORY) playbook/install_k8s_tools.yml

configure_firewall:
	ansible-playbook -i $(ANSIBLE_INVENTORY) playbook/configure_firewall.yml

init_master:
	ansible-playbook -i $(ANSIBLE_INVENTORY) playbook/init_k8s_master.yml

join_workers:
	ansible-playbook -i $(ANSIBLE_INVENTORY) playbook/join_k8s_workers.yml

install_flannel:
	ansible-playbook -i $(ANSIBLE_INVENTORY) playbook/install_flannel.yml

