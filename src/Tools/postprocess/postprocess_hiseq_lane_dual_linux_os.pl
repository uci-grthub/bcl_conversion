
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
	echo postprocess_hiseq_lane_ubuntu-22-04_test_gzip.pl $1 $2 $3 $4 $5
	/home/sequser/Facility/Tools/postprocess_hiseq_lane_ubuntu-22-04_test_gzip.pl $1 $2 $3 $4 $5
elif [ "$OS_NAME" == 'centos' ]; then
	echo Run Centos script
	echo postprocess_hiseq_lane_centos7_test_gzip.pl $1 $2 $3 $4 $5
	/home/sequser/Facility/Tools/postprocess_hiseq_lane_centos7_test_gzip.pl $1 $2 $3 $4 $5
else
	echo Unknow OS
fi

