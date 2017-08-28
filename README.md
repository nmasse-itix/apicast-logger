# An Apicast module that logs API requests and responses

## Description

This project is an [Apicast](https://github.com/3scale/apicast/) module
that logs API requests and responses for non-repudiation purposes.

## How it works

This Apicast module intercepts API requests and sends them to a syslog server.
The request, response, headers and additional information are serialized
as JSON and sent to a syslog server.

## Pre-requisites

This projects requires :
- an [Apicast](https://github.com/3scale/apicast/) gateway
- a syslog server (such as [syslog-ng](https://github.com/balabit/syslog-ng) or [rsyslog](https://github.com/rsyslog/rsyslog))
- the [lua-resty-logger-socket](https://github.com/cloudflare/lua-resty-logger-socket) module

## Installation

If not already done, start your syslog server and configure it to listen
for TCP connections on port 601. An exemple is given below with `syslog-ng`:

```
oadm policy add-scc-to-user privileged -z default
oc new-app balabit/syslog-ng --name syslog-ng
oc volume dc/syslog-ng --add --name log --type emptyDir --mount-path /var/log/
oc create configmap syslog-ng --from-file=syslog-ng.conf
oc volume dc/syslog-ng --add --name=conf --mount-path /etc/syslog-ng/conf.d/ --type=configmap --configmap-name=syslog-ng
```

Then, update your `apicast-{staging,production}` to embed the required code, module and environment variables.

Put `resolver.conf` in `/opt/app-root/src/apicast.d/resolver.conf`:
```
oc create configmap resolver --from-file=resolver.conf
oc volume dc/apicast-staging --add --name=resolver --mount-path /opt/app-root/src/apicast.d/ --type=configmap --configmap-name=resolver
```

Put the `lua-resty-logger-socket` module in `/opt/app-root/src/src/resty/logger/`:
```
git clone https://github.com/cloudflare/lua-resty-logger-socket.git
oc create configmap lua-resty-logger-socket --from-file=lua-resty-logger-socket/lib/resty/logger/socket.lua
oc volume dc/apicast-staging --add --name=lua-resty-logger-socket --mount-path /opt/app-root/src/src/resty/logger/ --type=configmap --configmap-name=lua-resty-logger-socket
```

Put the `verbose.lua` module in `/opt/app-root/src/src/custom/`:
```
oc create configmap apicast-logging --from-file=verbose.lua
oc volume dc/apicast-staging --add --name=apicast-logging --mount-path /opt/app-root/src/src/custom/ --type=configmap --configmap-name=apicast-logging
```

Set the configuration required by `verbose.lua` as environment variables and re-deploy apicast:
```
oc env dc/apicast-staging APICAST_MODULE=custom/verbose
oc env dc/apicast-staging SYSLOG_PROTOCOL=tcp
oc env dc/apicast-staging SYSLOG_PORT=601
oc env dc/apicast-staging SYSLOG_HOST=syslog-ng
oc rollout latest apicast-staging
```

## Message format

The requests and responses are serialized as follow:

```
{
  "request": {
    "request_id": "3b1b0d[...]",           # The unique ID of the request
    "raw": "R0VUIC8/dXN[...]",             # The raw request (request line + headers), base64 encoded
    "headers": {                           # The request headers as an object
      "host": "echo-api.3scale.net",
      "accept": "*/*",
      "user-agent": "curl/7.54.0"
    },
    "body": "3b1b0d587[...]",              # The body of the request, base64 encoded
    "method": "GET",                       # HTTP Method
    "start_time": 1503929520.684,          # The time at which the request has been received
    "uri_args": {                          # The decoded querystring as an object
      "foo": "bar"
    },
    "http_version": 1.1                    # The version of the HTTP protocol used to submit the request
  },
  "response": {
    "headers": {                           # The response headers as an object
      "cache-control": "private",
      "content-type": "application/json",
      "x-content-type-options": "nosniff",
      "connection": "keep-alive",
      "content-length": "715",
      "vary": "Origin"
    },
    "body": "ewogICJtZXRob2Qi[...]",       # The body of the response, base64 encoded
    "status": 200                          # The HTTP Status Code
  },
  "upstream": {                            # See http://nginx.org/en/docs/http/ngx_http_upstream_module.html#variables
    "response_length": "715",
    "header_time": "0.352",                             
    "addr": "107.21.49.219:443",
    "response_time": "0.352",
    "status": "200",
    "connect_time": "0.261"
  },
}
```

## Development

First of all, setup your development environment as explained [here](https://github.com/3scale/apicast/tree/master#development--testing).

Then, issue the following commands :
```
git clone TODO
git clone https://github.com/3scale/apicast.git
cd apicast
git checkout -b 3.0-stable
luarocks make apicast/*.rockspec --local
export THREESCALE_DEPLOYMENT_ENV=sandbox
export THREESCALE_PORTAL_ENDPOINT=https://<YOUR-TOKEN-HERE>@<YOUR-TENANT-HERE>-admin.3scale.net
export SYSLOG_HOST=localhost
export SYSLOG_PORT=601
export SYSLOG_PROTOCOL=tcp

ln -s ../apicast-logger custom
export APICAST_MODULE=custom/verbose

bin/apicast -vvvv -i 0 -m off
```

## Troubleshooting

When troubleshooting, keep in mind that the underlying `lua-resty-logger-socket`
module is asynchronous. When the logs cannot be sent to the syslog server,
the error is caught **ONLY UPON THE NEXT REQUESTS**. So, you might have to send
a couple requests before seeing errors in the logs.

If you need to troubleshoot DNS issue :
```
dig syslog-ng.3scale.svc.cluster.local
dig -p5353 @127.0.0.1 syslog-ng.3scale.svc.cluster.local
```