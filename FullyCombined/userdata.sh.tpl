#!/bin/bash

yum update -y
yum install -y git nginx

curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs

cd /home/ec2-user

git clone https://github.com/514-2255-2-team2/AmplifyUI

cd AmplifyUI/Amplify-React-UI

cat <<EOF > .env
VITE_API_BASE_URL=${api_base_url}
EOF

npm install
npm run build

rm -rf /usr/share/nginx/html/*
cp -r dist/* /usr/share/nginx/html/

systemctl enable nginx
systemctl start nginx
