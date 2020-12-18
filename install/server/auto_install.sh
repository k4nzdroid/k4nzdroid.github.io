#!/bin/bash
set -e

################################################################################
# 安装依赖
################################################################################

# 关闭 SELinux

# 安装依赖
# yum install -y epel-release
# yum install -y gcc expect ansible python-pip python-devel smartmontools dmidecode libselinux-python git rsync dos2unix
# yum install -y openssl openssl-devel openldap-devel

apt-get install -y gcc expect ansible python-pip-whl python-dev-is-python2 smartmontools dmidecode git rsync dos2unix
apt-get install -y openssl

################################################################################
# 初始化环境目录
################################################################################

main_dir="/opt/opsrc"
adminset_dir="$main_dir/application"
data_dir="$main_dir/data"
config_dir="$main_dir/config"
logs_dir="$main_dir/log"

mkdir -p $adminset_dir

mkdir -p $data_dir/scripts
mkdir -p $data_dir/files
mkdir -p $data_dir/ansible/playbook
mkdir -p $data_dir/ansible/roles

mkdir -p $config_dir
mkdir -p $config_dir/webssh

mkdir -p $logs_dir
mkdir -p $logs_dir/execlog

mkdir -p $main_dir/pid

# 分发代码
rsync --delete --progress -ra --exclude '.git' ./ $adminset_dir
pwd
exit

scp $adminset_dir/install/server/ansible/ansible.cfg /etc/ansible/ansible.cfg

# 安装 MySQL
yum install -y mariadb-server mariadb-devel
/bin/systemctl start mariadb
mysql -e "CREATE DATABASE if not exists adminset DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
/bin/systemctl enable mariadb.service

# 安装 MongoDB
yum install -y mongodb mongodb-server
/bin/systemctl enable mongod.service
/bin/systemctl start mongod.service

# 安装主程序
echo "####install adminset####"
mkdir -p  ~/.pip
cat <<EOF > ~/.pip/pip.conf
[global]
index-url = http://mirrors.aliyun.com/pypi/simple/

[install]
trusted-host=mirrors.aliyun.com
EOF
pip install -U pip
pip install --ignore-installed enum34==1.1.6
pip install --ignore-installed ipaddress==1.0.18
pip install kombu==4.2.1
pip install celery==4.2.1
pip install billiard==3.5.0.3
pip install pytz==2017.3
pip install setuptools==39.2.0
cd $adminset_dir/vendor/django-celery-results-master
python setup.py build
python setup.py install

cd $adminset_dir
pip install -r requirements.txt
python manage.py makemigrations
python manage.py migrate
echo "please create your adminset' super admin:"
#python manage.py createsuperuser
source /etc/profile
/usr/bin/mysql -e "insert into adminset.accounts_userinfo (password,username,email,is_active,is_superuser) values ('pbkdf2_sha256\$24000\$2odRjOCV1G1V\$SGJCqWf0Eqej6bjjxusAojWtZkz99vEJlDbQHUlavT4=','admin','admin@126.com',1,1);"
scp $adminset_dir/install/server/adminset.service /usr/lib/systemd/system
/bin/systemctl enable adminset.service

# install webssh
cd $adminset_dir/vendor/webssh/
/usr/bin/env python setup.py install
scp /var/opt/adminset/main/install/server/webssh/webssh.service /usr/lib/systemd/system/webssh.service
/bin/systemctl enable webssh.service

# 安装 Redis
echo "####install redis####"
yum install redis -y
/bin/systemctl start redis
/bin/systemctl enable redis.service

# 安装celery
echo "####install celery####"
mkdir -p $config_dir/celery
scp $adminset_dir/install/server/celery/beat.conf $config_dir/celery/beat.conf
scp $adminset_dir/install/server/celery/celery.service /usr/lib/systemd/system
scp $adminset_dir/install/server/celery/start_celery.sh $config_dir/celery/start_celery.sh
scp $adminset_dir/install/server/celery/beat.service /usr/lib/systemd/system
chmod +x $config_dir/celery/start_celery.sh
/bin/systemctl daemon-reload
/bin/systemctl enable celery.service
/bin/systemctl enable beat.service
/bin/systemctl start celery.service
/bin/systemctl start beat.service

# 安装nginx
echo "####install nginx####"
yum install nginx -y
scp $adminset_dir/install/server/nginx/adminset.conf /etc/nginx/conf.d
scp $adminset_dir/install/server/nginx/nginx.conf /etc/nginx
/bin/systemctl start nginx.service
/bin/systemctl enable nginx

# create ssh config
echo "create ssh-key, you could choose no if you had have ssh key"
if [ ! -e ~/.ssh/id_rsa.pub ]
then
    ssh-keygen -q -N "" -t rsa -f /root/.ssh/id_rsa
else
    echo "you had already have a ssh rsa file."
fi
scp $adminset_dir/install/server/ssh/config ~/.ssh/config


# 完成安装
echo "#######Waiting Starting Service##############"
/bin/systemctl daemon-reload
/bin/systemctl restart mariadb
/bin/systemctl restart celery
/bin/systemctl restart beat
/bin/systemctl restart mongod
/bin/systemctl restart webssh
/bin/systemctl restart nginx
/bin/systemctl restart sshd
/bin/systemctl restart adminset

