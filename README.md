# Athlete Face Match Instructions

## OPTION 1: AMI Setup

### Step 1 — Launch EC2 from AMI

Launch a new EC2 instance using the "514-Team2-GameFace-SetupTeardown" AMI that has been shared with you.

Specify your AWS key pair, and leave all other settings as default. 

### Step 2 — Connect and Authenticate EC2

Connect to the EC2 instance through a CloudShell session. 

Create an AWS access key, you will need the Access Key ID and Secret Key. 

```bash
aws configure
```

Provide your Access Key ID when prompted, then Secret Key, then set your default region to us-east-1. Other fields can be left blank.

### Step 3 — Set Your Key Pair

Use an existing key pair or create a new one. Replace `YOUR_KEY` near the bottom of main.tf with the name of your key pair, then run:

```bash
sed -i 's/.*key_name.*/  key_name      = "YOUR_KEY"/' main.tf
```

Confirm the change was applied:

```bash
grep -n 'key_name' main.tf
```

### Step 4 - Run Initalize Terraform

```bash
terraform init
```

### Step 5 - Run Apply Terraform

```bash
terraform apply
```

You will be prompted to enter an email to recieve the SNS noticaitons to so enter your email

### Step 6 - View the App

The terminal will output the react_app_public_ip put that into the browser to view the application



## OPTION 2: Manual Setup

### Step 1 — Open CloudShell

### Step 2 — Clone the Repository

```bash
git clone https://github.com/514-2255-2-team2/Main-Terraform.git
cd Main-Terraform/FullyCombined
```

### Step 3 — Set Your Key Pair

Use an existing key pair or create a new one. Replace `YOUR_KEY` near the bottom of main.tf with the name of your key pair, then run:

```bash
sed -i 's/.*key_name.*/  key_name      = "YOUR_KEY"/' main.tf
```

Confirm the change was applied:

```bash
grep -n 'key_name' main.tf
```

### Step 4 — Install Terraform

Run the following commands in order:

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform
```

Verify the installation:

```bash
terraform -version
```

### Step 5 - Run Initalize Terraform

```bash
terraform init
```

### Step 6 - Run Apply Terraform

```bash
terraform apply
```

You will be prompted to enter an email to recieve the SNS noticaitons to so enter your email

### Step 7 - View the App

The terminal will output the react_app_public_ip put that into the browser to view the application
