if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
	OS_NAME=$ID
fi
echo $NAME
echo $VERSION_ID
echo $OS_NAME

if [ "$OS_NAME" == 'ubuntu' ]; then
	echo Run Ubuntu script
elif [ "$OS_NAME" == 'centos' ]; then
	echo Run Centos script
else
	echo Unknow OS
fi

