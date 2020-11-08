#!/bin/bash

nb_var=$#
container_name=$1
distrib_name=$2
release_name=$3
dev_name=$4
container_ip=$5
container_gateway=$6


mac_addr=$(sudo ip addr show dev $dev_name | grep link |awk '{print $2}')

if [ $nb_var != 6 ]
then
    echo "erreur: nombre de paramètres incorrects"
    echo "./script-perso container_name distrib_name release_name dev_name container_ip container_gateway"
else

    netplan_invite="/etc/netplan/10-lxc.yaml"
    config_container="/var/lib/lxc/$container_name/config"


    # creation du conteneur
    sudo lxc-create -t download -n $container_name -- -d $distrib_name -r $release_name -a amd64
    echo "conteneur $container_name créé"

    # modification de l'interface en mode physique
    sudo sed -i "s/lxc.net.0.type.*/lxc.net.0.type = phys/g" $config_container
    sudo sed -i "s/lxc.net.0.link.*/lxc.net.0.link = $dev_name/g" $config_container
    sudo sed -i "s/lxc.net.0.hwaddr.*/lxc.net.0.hwaddr = $mac_addr/g" $config_container
    sudo sed -i "s/lxc.net.0.flags.*/lxc.net.0.flags = up/g" $config_container
    echo "interface en mode physique activée"


    # FILES
    netplan_file="
# This is the network config written by 'subiquity'
network:
  ethernets:
    $dev_name:
      addresses: [$container_ip/24]
      gateway4: $container_gateway
      nameservers:
        addresses:
        - 8.8.8.8
  version: 2"

    container_file="
# Memory limit to 256 Mo
lxc.cgroup.memory.limit_in_bytes=268435456

# Utilisation de 50 pourcent du processeur
lxc.cgroup.cpu.cfs_quota_us=500000
lxc.cgroup.cpu.cfs_period_us=1000000"

    lxc-start -n $container_name

    # modification de netplan sur l'invité
    lxc-attach -n $container_name -- /bin/bash << INVITE
    echo "$netplan_file" > $netplan_invite
    netplan apply
INVITE
    echo "modification de netplan effectuée"
    lxc-stop -n $container_name
    lxc-start -n $container_name

    # limitation des ressources
    echo "$container_file" >> $config_container
    echo "limitation des ressources effectuée"

    # installation du serveur apache
    lxc-attach -n $container_name -- /bin/bash << INVITE
    apt-get update > /dev/null && apt-get install apache2 -y > /dev/null
INVITE
    echo "installation d'apache effectuée"

    # vérification site web accessible
    request_result=$(curl -I http://$container_ip:80 | grep HTTP |awk '{print $2}')

    if [ $request_result == "200" ]
    then
        echo "adresse http://$container_ip:80 accessible"
    else
        echo "le serveur web n'est pas accessible"
    fi
fi