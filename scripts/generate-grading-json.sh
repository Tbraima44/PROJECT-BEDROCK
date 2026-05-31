#!/bin/bash

Script to generate grading.json for submission

cd ../terraform
terraform output -json > ../grading.json
echo "grading.json generated successfully!"
