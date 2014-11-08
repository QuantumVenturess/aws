require "rubygems"
require "aws-sdk"

AWS.config(
  access_key_id:     ENV["AWS_ACCESS_KEY_ID"],
  secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
)

s3 = AWS::S3.new

bucket_name = "tommydang"
obj_name    = "will_paginate.txt"

document = s3.buckets[bucket_name].objects[obj_name]

File.open(obj_name, "w") do |f|
  f.write document.read
end

puts "'#{obj_name}' copied from S3."
