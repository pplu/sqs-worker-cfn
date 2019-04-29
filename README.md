# NAME

SQS::Worker::CloudFormationResource - A helper to develop your own custom CloudFormation resources

# DESCRIPTION

This is a [SQS::Worker](https://metacpan.org/pod/SQS::Worker) role that helps you develop SNS-based CloudFormation Custom Resources that deliver to an
SQS queue.

More information on SNS based Custom Resources here: [https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources-sns.html](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources-sns.html)

This module takes care of lots of repetitive work when building an SNS-based CloudFormation Custom Resource.

# USAGE

    package MyCustomResource {
      use Moose;
      with 'SQS::Worker', 'SQS::Worker::SNS', 'SQS::Worker::CloudFormationResource';

      sub create_resource {
        my ($self, $request, $result) = @_;
        # $request is a SQS::Worker::CloudFormationResource::Request
        # $result  is a SQS::Worker::CloudFormationResource::Response
      }

      sub update_resource {
        my ($self, $request, $result) = @_;
      }

      sub delete_resource {
        my ($self, $request, $result) = @_;
      }
    }

# WRITING A CUSTOM RESOURCE

The worker will poll the SQS queue for you, invoking `create_resource`, `update_resource`
or `delete_resource` in function of what is happening in CloudFormation, passing them a 
request object with all the information coming from CloudFormation. Look at [SQS::Worker::CloudFormationResource::Request](https://metacpan.org/pod/SQS::Worker::CloudFormationResource::Request)
for more information on what information a request has. result is an object that has [SQS::Worker::CloudFormationResource::Response](https://metacpan.org/pod/SQS::Worker::CloudFormationResource::Response).
Set the appropiate properties of the response object. The response object will be returned to CloudFormation.

    $result->set_success('Created resource'); # the success message will show in the cloudformation log
    $result->PhysicalResourceId('resource-123456');
    $result->Data({
      Color => 'Blue',
    });

When calling update\_resource: `PhysicalResourceId` will already be initialized to the PhisicalResourceId that was set in `create_resource`,
meaning that if it isn't updated, CloudFormation considers the update as a in-place replacement. If a new `PhysicalResourceId` is assigned,
CloudFormation considers the operation as a replacement. Later on, CloudFormation will send a Delete for the old PhysicalResourceId, which
shouldn't be handled as any special case: the `delete_resource` will be invoked.

Unhandled exceptions in any `resource_*` methods will be handled, returning a generic "Internal Error" text to CloudFormation,
considering the resource FAILED.

Unhandled exceptions in `resource_create` will treat the resource creation as a special case. Since CloudFormation requires a Physical ID to
be sent, even if we're signalling a FAILURE, SQS::Worker::CloudFormationResource will use an internal Physical ID, that will never be delivered
to the `delete_resource` method (it will be intercepted and dropped before getting processed).

# SETTING UP A CUSTOM RESOURCE

To use the resource in CloudFormation, you have to provision an SNS topic that delivers it's messages
to an SQS queue. You can setup an SNS topic with the bundled `examples/sns-topic-for-cloudformation.json` file (which will output
all the data you need to run the worker

    spawn_worker --worker CustomResourceExample1 --queue_url=http://..../QueueURL --region=eu-west-1 --log_conf log.conf

# USING YOUR CUSTOM RESOURCE

    { "resources": [
      "Custom1": {
        "Type": "Custom::MyCustomResource",
        "Version": "1.0",
        "Properties": {
          "ServiceToken": "arn:of the SNS topic for the custom resource",
          ... Resource Properties ...
        }
      }
    ] }

The data you have set in the `Data` property of the response object will be accessible in CloudFormation templates via the GetAtt
function.

    { "Fn::GetAtt": [ "Custom1", "Color" ] }

# METHODS

## create\_resource($request, $response)

Implement this method in your Custom Resource worker class. All properties sent by CloudFormation will be in `$request` of type 
[SQS::Worker::CloudFormationResource::Request](https://metacpan.org/pod/SQS::Worker::CloudFormationResource::Request). This method should modify `$response` to control what will be sent to CloudFormation.
The following can be done:

Either call `set_success` or `set_failed`

Set attribute `PhysicalResourceId` (`$response-&gt;('resource-123456');`)

Set attribute `Data` to a Hashref with the keys and values that CloudFormation will treat as this objects attributes

## update\_resource

Implement this method in your Custom Resource worker class.

## delete\_resource

Implement this method in your Custom Resource worker class.

Either call `set_success` or `set_failed` to indicate that the resource was deleted or not

# SEE ALSO

[SQS::Worker](https://metacpan.org/pod/SQS::Worker)

[https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources-sns.html](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources-sns.html)

[Paws::SQS](https://metacpan.org/pod/Paws::SQS)

# COPYRIGHT and LICENSE

Copyright (c) 2018 by CAPSiDE

This code is distributed under the Apache 2 License. The full text of the license can be found in the LICENSE file included with this module.

# AUTHORS

    Jose Luis Martinez
    JLMARTIN
    jlmartinez@capside.com
