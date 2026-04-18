variable "project_name" {
 default = "prakas_lamda_function_project"
 description = "This is the project name for the lamda functions" 
 type = string 
}

variable "environment" {
    default = "dev"
    description = "This is the environment name of the project"
    type = string
}


variable "aws_region" {
    default = "ap-south-1"
    description = "AWS region for the resource"
    type = string
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 1024
}

variable "allowed_origins" {
  description = "Allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}