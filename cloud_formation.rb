# http://docs.aws.amazon.com/sdkforruby/api/frames.html

require "aws-sdk-v1"
require "aws-sdk"
require "json"

# Functions
folder = "test"
folder = "sample"
folder = "production"
def string_from_json_file(file_name)
  name = "#{folder}/#{file_name}.json"
  if File.exists? name
    file = File.open name
    data = file.read
    file.close
    data.to_str
  else
    ""
  end
end

# Variables
image_id = "ami-3d50120d"

template_json     = string_from_json_file "template"
parameters_string = string_from_json_file "parameters"
resources_string  = string_from_json_file "resources"

["parameters", "mappings", "conditions", "resources", "outputs"].each do |key|
  template_json.gsub! Regexp.new("{{#{key}}}"), string_from_json_file(key)
end

[
  {
    regexp: /{{image_id}}/,
    value:  image_id
  }
].each do |hash|
  template_json.gsub! hash[:regexp], hash[:value]
end

now       = Time.now
timestamp = now.strftime("%Y%m%d%S%M%I")

credentials = Aws::Credentials.new(
  ENV["AWS_ACCESS_KEY_ID"],
  ENV["AWS_SECRET_ACCESS_KEY"]
)

region            = "us-west-2"
availability_zone = "us-west-2a"

client = Aws::CloudFormation::Client.new(
  credentials: credentials,
  region:      region
)
resource = Aws::CloudFormation::Resource.new(client: client)

puts template_json

stack = resource.create_stack(
  stack_name:    "stack-#{timestamp}",
  template_body: template_json
)

puts resource.stacks
