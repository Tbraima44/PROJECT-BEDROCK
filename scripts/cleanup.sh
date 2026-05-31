#!/bin/bash

Cleanup script to destroy all resources

Use with caution - this will delete all infrastructure

echo "WARNING: This will destroy all Project Bedrock resources"
read -p "Are you sure? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
cd ../terraform
terraform destroy
fi
