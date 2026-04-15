# Athlete Face Match Instructions

## Step 1 — Open CloudShell

## Step 2 — Clone the Repository

```bash
git clone https://github.com/514-2255-2-team2/Main-Terraform.git
cd Main-Terraform/FullyCombined
```

## Step 3 — Set Your Key Pair

Use an existing key pair or create a new one. Replace `YOUR_KEY` near the bottom of main.tf with the name of your key pair, then run:

```bash
sed -i 's/key_name = .*/key_name = "YOUR_KEY"/' main.tf
```

Confirm the change was applied:

```bash
grep -n 'key_name' main.tf
```

## Step 4 — Install Terraform

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

## Step 5 - Run Initalize Terraform

```bash
terraform init
```

## Step 6 - Run Apply Terraform

```bash
terraform apply
```

You will be prompted to enter an email to recieve the SNS noticaitons to so enter your email

## Step 7 - View the App

The terminal will output the react_app_public_ip put that into the browser to view the application
