#!/bin/bash

cmd_source="source /opt/osdeploy/your-admin-rc.sh"

# 配置主机转换成镜像文件后的文件名格式
# 未压缩镜像文件的后缀是no_compress.qcow2
# 压缩后镜像文件的后缀是compressed.qcow2
format_convertedfilename='/var/lib/nova/instances/${UUID}/${UUID}'


eval ${cmd_source}

# TODO: 输入可以用主机名
if [ "$1"x == ""x ]; then
  echo "请输入instance-uuid"
  read UUID
else
  UUID=$1
fi

filename_nocompress=`eval echo ${format_convertedfilename}`'.'`date +%s`'.no_compress.qcow2'
filename_compressed=`eval echo ${format_convertedfilename}`'.'`date +%s`'.compressed.qcow2'

echo "正在检查 instance UUID.." $UUID
host=`nova show $UUID |grep OS-EXT-SRV-ATTR:host|awk '{printf $4}'`
if [ $? != 0 ]; then
  echo "检查失败，请检查 UUID 是否有效"
  exit 1
fi

echo "正在确认 instance 是否已关机"

status=`nova show ${UUID}|grep " status "|grep "SHUTOFF"|wc -l`

#echo "status: "  $status
if [ ${status} != "1" ]; then
  echo "检查失败，请手动确认 instance 已关机"
  exit 1
fi

echo "正在检查 host "$host" 的连接状态"
ping "${host}" -c 3 >/dev/null
if [ $? != 0 ]; then
  echo "Ping 检查失败"
  exit 1
fi
eval ssh "${host} 'echo ${HOSTNAME}'"
if [ $? != 0 ]; then
  echo "SSH 连接检查失败"
  exit 1
fi

echo "请确认是否执行以下命令，将主机数据打包成镜像文件"
# 这一步生成的是非压缩状态，输出格式：qcow2
cmd_createimage='ssh '${host}' "qemu-img convert -O qcow2 /var/lib/nova/instances/'${UUID}'/disk '${filename_nocompress}'"'

echo ${cmd_createimage}

answer=""
until [ "${answer}"x == "Y"x ] || [ "${answer}"x == "n"x ]
do
  echo "[Y/n]?"
  read answer
done

if [ "${answer}"x == "Y"x ]; then
  echo "正在执行镜像转换..."
eval ${cmd_createimage}
else
  echo "Good bye!"
  exit 0
fi

echo "请选择 sysprep 清理方式。0:不清理；1:清理除 ssh-hostkey s 之外的选项（适用于无cloud-init环境）；2:全部清理（适用于cloud-init环境）"
# TODO: 不清理可以跳过
answer_sysprep=""
until [ "${answer_sysprep}"x == "0"x ] || [ "${answer_sysprep}"x == "1"x ] || [ "${answer_sysprep}"x == "2"x ]
do
  echo "[0/1/2]"
  read answer_sysprep
done

cmd_sysprep=""
if [ "${answer_sysprep}"x == "1"x ]; then
  cmd_sysprep='ssh '${host}' "virt-sysprep --enable abrt-data,bash-history,blkid-tab,crash-data,cron-spool,dhcp-client-state,dhcp-server-state,dovecot-data,firstboot,hostname,logfiles,machine-id,mail-spool,net-hostname,net-hwaddr,pacct-log,package-manager-cache,pam-data,password,puppet-data-log,random-seed,rhn-systemid,rpm-db,samba-db-log,script,smolt-uuid,ssh-userdir,sssd-db-log,tmp-files,udev-persistent-net,utmp,yum-uuid -a '${filename_nocompress}'"'
elif [ "${answer_sysprep}"x == "2"x]; then
  cmd_sysprep='ssh '${host}' "virt-sysprep --enable abrt-data,bash-history,blkid-tab,crash-data,cron-spool,dhcp-client-state,dhcp-server-state,dovecot-data,firstboot,hostname,logfiles,machine-id,mail-spool,net-hostname,net-hwaddr,pacct-log,package-manager-cache,pam-data,password,puppet-data-log,random-seed,rhn-systemid,rpm-db,samba-db-log,script,smolt-uuid,ssh-userdir,sssd-db-log,tmp-files,udev-persistent-net,utmp,yum-uuid,ssh-hostkeys -a '${filename_nocompress}'"'
fi

echo "请确认清理命令："

echo ${cmd_sysprep}

answer=""
until [ "${answer}"x == "Y"x ] || [ "${answer}"x == "n"x ]
do
  echo "[Y/n]?"
  read answer
done

if [ "${answer}"x == "n"x ]; then
  echo "Good bye!"
  exit 0
fi

eval ${cmd_sysprep}

echo "是否对镜像文件进行压缩？（推荐）"
answer=""
until [ "${answer}"x == "Y"x ] || [ "${answer}"x == "n"x ]
do
  echo "[Y/n]?"
  read answer
done

if [ "${answer}"x == "n"x ]; then
  # TODO: 跳过，而不是直接say goodbye
  echo "Good bye!"
  exit 0
fi

echo "请确认压缩命令:"
cmd_compress='ssh '${host}' "virt-sparsify -x '${filename_nocompress}' --convert qcow2 '${filename_compressed}' --compress"'
echo ${cmd_compress}

answer=""
until [ "${answer}"x == "Y"x ] || [ "${answer}"x == "n"x ]
do
  echo "[Y/n]?"
  read answer
done

if [ "${answer}"x == "Y"x ]; then
  echo "正在压缩..."
  eval ${cmd_compress}
else
  echo "Good bye!"
fi

echo '压缩完毕，输出文件路径：'${filename_compressed}

echo "是否将镜像上传本环境 glance ？"

answer=""

until [ "${answer}"x == "Y"x ] || [ "${answer}"x == "n"x ]
do
  echo "[Y/n]?"
  read answer
done

if [ "${answer}"x == "n"x ]; then
  echo "Good bye!"
  exit 0
fi

echo "请输入镜像名（例：ubuntu_14.04_x86_64_V2.3.1，不含中文）"
read image_name
# TODO: 镜像名检查

cmd_uploadglance='ssh '${host}' "'${cmd_source}' && glance image-create --name '${image_name}' --file '${filename_compressed}' --disk-format qcow2 --container-format bare --is-public True --progress"'

echo "请确认镜像上传命令:"

echo ${cmd_uploadglance}

answer=""
until [ "${answer}"x == "Y"x ] || [ "${answer}"x == "n"x ]
do
  echo "[Y/n]?"
  read answer
done

if [ "${answer}"x == "Y"x ]; then
  echo "正在上传..."
  eval ${cmd_uploadglance}
else
  echo "Good bye!"
fi

echo '上传完成，请使用glance image-update ${image_id} --property ${key}=${value}命令更新镜像属性'
# 如对多数 Linux 镜像：glance image-update 镜像id --property os_type=linux; glance image-update 镜像id --property 
# TODO: 文件清理

