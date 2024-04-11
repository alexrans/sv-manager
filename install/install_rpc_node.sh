#!/bin/bash
#set -x -e

echo "###################### 警告!!! ######################"
echo "###   此脚本将为 Solana 区块链启动一个 RPC 节点    ###"
echo "###   并连接到监控仪表板                          ###"
echo "###   在 solana.thevalidators.io                    ###"
echo "########################################################"

install_rpc () {

  echo "### 请选择集群: ###"
  select cluster in "mainnet-beta" "testnet"; do
      case $cluster in
          mainnet-beta ) inventory="mainnet.yaml"; break;;
          testnet ) inventory="testnet.yaml"; break;;
      esac
  done

  echo "请输入您的 RPC 节点名称: "
  read VALIDATOR_NAME
  read -e -p "请输入您的验证器密钥对文件的完整路径，或留空，然后将创建密钥对: " -i "" PATH_TO_VALIDATOR_KEYS


  read -e -p "输入新的 RAM 磁盘大小，GB（推荐大小：服务器 RAM 减去 16GB）：" -i "48" RAM_DISK_SIZE
  read -e -p "输入新的服务器交换文件大小，GB（推荐大小：与服务器 RAM 相等）：" -i "64" SWAP_SIZE

  rm -rf sv_manager/

  if [[ $(which apt | wc -l) -gt 0 ]]
  then
  pkg_manager=apt
  elif [[ $(which yum | wc -l) -gt 0 ]]
  then
  pkg_manager=yum
  fi

  echo "更新软件包..."
  $pkg_manager update
  echo "安装 ansible、curl、unzip..."
  $pkg_manager install ansible curl unzip --yes

  ansible-galaxy collection install ansible.posix
  ansible-galaxy collection install community.general

  echo "下载 Solana 验证器管理器版本 $sv_manager_version"
  cmd="https://github.com/mfactory-lab/sv-manager/archive/refs/tags/$sv_manager_version.zip"
  echo "开始 $cmd"
  curl -fsSL "$cmd" --output sv_manager.zip
  echo "解压"
  unzip ./sv_manager.zip -d .

  mv sv-manager* sv_manager
  rm ./sv_manager.zip
  cd ./sv_manager || exit
  cp -r ./inventory_example ./inventory

  ansible-playbook --connection=local --inventory ./inventory/$inventory --limit localhost_rpc  playbooks/pb_config.yaml --extra-vars "{ \
  'validator_name':'$VALIDATOR_NAME', \
  'local_secrets_path': '$PATH_TO_VALIDATOR_KEYS', \
  'swap_file_size_gb': $SWAP_SIZE, \
  'ramdisk_size_gb': $RAM_DISK_SIZE, \
  'fail_if_no_validator_keypair: False'
  }"

  if [ ! -z $solana_version ]
  then
    SOLANA_VERSION="--extra-vars {\"solana_version\":\"$solana_version\"}"
  fi
  if [ ! -z $extra_vars ]
  then
    EXTRA_INSTALL_VARS="--extra-vars {$extra_vars}"
  fi
  if [ ! -z $tags ]
  then
    TAGS="--tags {$tags}"
  fi

  ansible-playbook --connection=local --inventory ./inventory/$inventory --limit localhost_rpc  playbooks/pb_install_validator.yaml --extra-vars "@/etc/sv_manager/sv_manager.conf" $SOLANA_VERSION $EXTRA_INSTALL_VARS $TAGS

  echo "### '卸载 ansible ###"

  $pkg_manager remove ansible --yes

  echo "### 检查您的仪表板：https://solana.thevalidators.io/d/e-8yEOXMwerfwe/solana-monitoring?&var-server=$VALIDATOR_NAME"

}


while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare ${param}="$2"
        #echo $1 $2 // Optional to see the parameter:value result
   fi

  shift
done

sv_manager_version=${sv_manager_version:-latest}

echo "安装 sv manager 版本 $sv_manager_version"

echo "此脚本将启动 Solana RPC 节点。继续吗？"
select yn in "是" "否"; do
    case $yn in
        是 ) install_rpc "$sv_manager_version" "$extra_vars" "$solana_version" "$tags"; break;;
        否 ) echo "安装中止。不会进行任何更改。"; exit;;
    esac
done
