#!/usr/bin/env bash

# exit on non-zero exit code
set -e
set -o pipefail

# exit on unbound variables
set -u

COLLECTOR_DIR=/usr/local/logicmonitor

if id -u logicmonitor
then
	COLLECTOR_USER=logicmonitor
else
	COLLECTOR_USER=root
fi

# exit if required commands are not present
if ! command -v curl &> /dev/null
then
	echo "This script requires curl, which is not found on this system, exiting."
	exit
fi

if ! command -v dpkg &> /dev/null
then
	echo "This script requires dpkg, which is not found on this system, exiting."
	exit
fi

if ! command -v unzip &> /dev/null
then
	echo "This script requires unzip, which is not found on this system, exiting."
	exit
fi


echo "Assuming collector user is $COLLECTOR_USER"
echo "Assuming collector directory is at $COLLECTOR_DIR"
echo "If this is wrong, edit the variables at the top of this script before continuing"
read -n 1 -s -r -p "Press any key to continue"

# Versions
CHROME_DRIVER_VERSION=`curl -sS https://chromedriver.storage.googleapis.com/LATEST_RELEASE`

# Remove existing downloads and binaries so we can start from scratch.
if test -f /usr/local/bin/chromedriver; then
	sudo rm /usr/local/bin/chromedriver
fi

#Download latest package of Chrome
CHROME_PKG_TMP=$(mktemp)
curl -sS https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o $CHROME_PKG_TMP
sudo dpkg -r google-chrome-stable
sudo dpkg -i $CHROME_PKG_TMP

# Install ChromeDriver.
CHROME_DRIVER_TMP=$(mktemp)
curl -sS https://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_linux64.zip -o $CHROME_DRIVER_TMP
CHROME_DRIVER_TMP_UNZIP_DIR=$(mktemp -d)
unzip $CHROME_DRIVER_TMP -d $(CHROME_DRIVER_TMP_UNZIP)
sudo mv -f $CHROME_DRIVER_TMP_UNZIP/chromedriver /usr/local/bin/chromedriver
sudo chown root:root /usr/local/bin/chromedriver
sudo chmod 0755 /usr/local/bin/chromedriver

# Download Selenium
SELENIUM_JAR_URL=$(curl -sS https://www.selenium.dev/downloads/ | grep "Latest stable" | grep -o "https://.*jar")
SELENIUM_JAR_TMP=$(mktemp)
curl -sS $SELENIUM_JAR_URL -o $SELENIUM_JAR_TMP

# Create local/lib if it doesn't exist
sudo mkdir -p $COLLECTOR_DIR/agent/local/lib

# Move Selenium to LogicMonitor Collector's local/lib directory
mv -f $SELENIUM_JAR_TMP $COLLECTOR_DIR/agent/local/lib/selenium-server-standalone.jar

# Add an entry in wrapper.conf if necessary
if ! grep -q "wrapper.java.classpath..*=../local/lib/selenium-server-standalone.jar" $COLLECTOR_DIR/agent/conf/wrapper.conf
then
	last_index=grep -q "wrapper.java.classpath" $COLLECTOR_DIR/agent/conf/wrapper.conf | cut -d '=' -f1 | cut -d'.' -f4 | sort -n | tail -n1
	next_index=$((last_index+1))
	echo "# Added by logicmonitor_selenium_debian.sh from github.com/jw-cohen/lm-scripts" >> $COLLECTOR_DIR/agent/conf/wrapper.conf
	echo "wrapper.java.classpath.$next_index=../local/lob/selenium-server-standalone.jar" >> $COLLECTOR_DIR/agent/conf/wrapper.conf
else

	echo "Selenium already in wrapper config - exiting."
fi

#Now let's restart the collector
echo "Restarting Collector"
sudo systemctl restart logicmonitor-agent.service
echo "Collector has restarted"
