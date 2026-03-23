#!/bin/bash

yum update -y

curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs git nginx

cd /home/ec2-user

git clone https://github.com/514-2255-2-team2/AmplifyUI

cd YOUR_REPO/Amplify-React-UI

npm install
npm run build

rm -rf /usr/share/nginx/html/*
cp -r dist/* /usr/share/nginx/html/

systemctl enable nginx
systemctl start nginx