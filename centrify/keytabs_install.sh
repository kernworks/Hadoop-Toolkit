#!/bin/env bash
########################################
# This script is designed to be used with keytabs_prepare.sh
#
# After the Active Directory Admin creates the keytabs using the script generated by
#    the keytabs_prepare.sh script. This script can be used to deploy them.
#
# You must have either root access with passwordless ssh between servers
#    or dzdo access to the chown command as well as ssh keys setup between servers.
#
# You must also have created a tar file containing headless keytabs.
#    This script will error if it does not find it and will tell you how to go about
#    creating what you need.
#
# This script will also attempt to deploy the jce policy files for Oralce JDK 1.7.0
#    This requires internet access. Alternatively you can download the file and host
#    it internally. Search for the 'wget' command in this script for the place to modify.
#
# This script does its best to secure keytabs but it is strongly recommended that you
#    go back and verify the protection.
#
# I AM NOT RESPONSIBLE FOR ANY ISSUES AS A RESULT OF USING THIS SCRIPT!
#
########################################

##GLOBALS
DIR=/etc/security/keytabs
JAVA17HOME=/usr/java/default
DZDO=''

usage() {
  echo "Usage: `basename $0`" >&2
  echo "       `basename $0` FQDN of server to deploy to" >&2
  echo '' >&2
  echo "See comments in this script for further help." >&2
}

if [ "$USER" = '' ]; then
  USER=`whoami`
fi

if !  ps -ef | grep ambari-server | grep -qv grep ; then
  echo "ERROR: This should be run on the ambari server" >&2
#  exit 99
fi

if [ "$USER" != "root" ]; then
  echo "WARNING: Not running as root user. This requires dzdo access to chown as root user." >&2
  DZDO='dzdo '
fi

#Check for a . character, if one exists, assume they entered a proper FQDN
if ! echo "$1" | egrep -q '\.'; then
  echo "ERROR: Invalid FQDN: '$1'" >&2
  usage
  exit 1
fi

if ! ssh -axo "BatchMode yes" $1 true >/dev/null 2>&1; then
  echo "ERROR: $1 not accessible via ssh or key is not installed" >&2
  exit 1
fi

#Uncomment if you want to validate $1 server is in a specific Centrify zone
#if ! ssh -ax $1 adinfo 2>/dev/null | egrep -iq 'hadoop'; then
#  echo "ERROR: $1 not in hadoop Centrify zone" >&2
#  exit 1
#fi

cd $DIR

if [ ! -d $DIR/new/$1 ]; then
  echo "ERROR: $DIR/new/$1 does not exist. Please run keytabs_prepare.sh first" >&2
  exit 99
fi

if [ ! -f $DIR/all/headless/headless.keytabs.tar ]; then
  echo "ERROR: $DIR/all/headless/headless.keytabs.tar is missing!" >&2
  echo "       Place any headless keytabs (hdfs, ambari-qa) in " >&2
  echo "       $DIR/all/headless" >&2
  echo "       Create a headless.keytabs.tar file there that contain" >&2
  echo "       the headless keytabs as well. Make sure to secure this." >&2
  exit 1
fi

echo "Preparing new keytabs..."

$DZDO chown -R $USER:hadoop $DIR/new/*
chmod -R 740 $DIR/new/*
chmod -R 440 $DIR/new/*.keytab
mv $DIR/new/$1 $DIR/all/

cd $DIR/all

tar -cf $1_keytabs.tar ./$1/*
chgrp hadoop $1_keytabs.tar
chmod 400 $1_keytabs.tar

echo "Preparing $1..."

ssh -ax $1 mkdir -p $DIR

scp -p $1_keytabs.tar $1:$DIR/
scp -p $DIR/all/headless/headless.keytabs.tar $1:$DIR/

echo ''
echo "Installing Updated Kerberos JAR Packages..."
ssh -ax $1 "cd /tmp
wget http://public-repo-1.hortonworks.com/ARTIFACTS/UnlimitedJCEPolicyJDK7.zip
unzip UnlimitedJCEPolicyJDK7.zip
cd UnlimitedJCEPolicy
$DZDO chown $USER $JAVA17HOME/jre/lib/security
$DZDO chown $USER $JAVA17HOME/jre/lib/security/*.jar
cp -p /tmp/UnlimitedJCEPolicy/*.jar $JAVA17HOME/jre/lib/security/
$DZDO chown root $JAVA17HOME/jre/lib/security/*.jar
$DZDO chown root $JAVA17HOME/jre/lib/security
cd /tmp
rm -f UnlimitedJCEPolicyJDK7.zip
rm -rf /tmp/UnlimitedJCEPolicy
"

echo ''
echo "Installing Keytabs on $1..."

ssh -ax $1 "cd $DIR
tar -xf $1_keytabs.tar
tar -xf headless.keytabs.tar
mv $DIR/$1/* $DIR/
rmdir $DIR/$1
chmod 400 ./*.keytab 2>/dev/null
chmod 440 ./spnego.* 2>/dev/null
chmod 440 ./*headless.keytab 2>/dev/null
$DZDO chgrp hadoop ./* 2>/dev/null
$DZDO chown ambari-qa smokeuser.* 2>/dev/null
$DZDO chown falcon falcon.* 2>/dev/null
$DZDO chown hdfs hdfs.* 2>/dev/null
$DZDO chown hdfs jn.* 2>/dev/null
$DZDO chown hdfs nn.* 2>/dev/null
$DZDO chown hdfs dn.* 2>/dev/null
$DZDO chown hive hive.* 2>/dev/null
$DZDO chown mapred jhs.* 2>/dev/null
$DZDO chown nagios nagios.* 2>/dev/null
$DZDO chown oozie oozie.* 2>/dev/null
$DZDO chown root spnego.* 2>/dev/null
$DZDO chown yarn rm.* 2>/dev/null
$DZDO chown yarn nm.* 2>/dev/null
$DZDO chown zookeeper zk.* 2>/dev/null
rm $DIR/*.tar 2>/dev/null
ls -al $DIR/*.keytab
"
echo ''

if  [ "$(ssh -ax $1 "md5sum $JAVA17HOME/jre/lib/security/local_policy.jar" | awk '{print $1}')" != '9dd69bcc7637d872121880c35437788d' ]; then
  echo "ERROR: $JAVA17HOME/jre/lib/security/local_policy.jar invalid" >&2
fi

if  [ "$(ssh -ax $1 "md5sum $JAVA17HOME/jre/lib/security/US_export_policy.jar" | awk '{print $1}')" != '3bb2e88a915b3cb003ca185357a92c16' ]; then
  echo "ERROR: $JAVA17HOME/jre/lib/security/US_export_policy.jar invalid" >&2
fi

echo "Done. Please verify all keytabs are installed."
