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

This project has been tested with Apicast v3.2. It may work with newer or older version
but it may require some minor changes.

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

Then, update your `apicast-staging` to embed the required code,
module and environment variables as explained:

Put `resolver.conf` in `/opt/app-root/src/apicast.d/resolver.conf`:
```
oc create configmap apicast.d --from-file=resolver.conf
oc volume dc/apicast-staging --add --name=apicastd --mount-path /opt/app-root/src/apicast.d/ --type=configmap --configmap-name=apicast.d
```

Put the `lua-resty-logger-socket` module in `/opt/app-root/src/src/resty/logger/`:
```
git clone https://github.com/cloudflare/lua-resty-logger-socket.git
oc create configmap lua-resty-logger-socket --from-file=lua-resty-logger-socket/lib/resty/logger/socket.lua
oc volume dc/apicast-staging --add --name=lua-resty-logger-socket --mount-path /opt/app-root/src/src/resty/logger/ --type=configmap --configmap-name=lua-resty-logger-socket
```

Put the `verbose.lua` module in `/opt/app-root/src/src/custom/`:
```
oc create configmap apicast-custom-module --from-file=verbose.lua
oc volume dc/apicast-staging --add --name=apicast-custom-module --mount-path /opt/app-root/src/src/custom/ --type=configmap --configmap-name=apicast-custom-module
```

Set the configuration required by `verbose.lua` as environment variables and re-deploy apicast:
```
oc env dc/apicast-staging APICAST_MODULE=custom/verbose
oc env dc/apicast-staging SYSLOG_PROTOCOL=tcp
oc env dc/apicast-staging SYSLOG_PORT=601
oc env dc/apicast-staging SYSLOG_HOST=syslog-ng.3scale.svc.cluster.local
oc rollout latest apicast-staging
```

**NOTE:** You need to adjust the value of `SYSLOG_HOST` to match your environment.
Namely, make sure you are using a FQDN that resolves to your syslog server.
If the syslog server is deployed in OpenShift, it needs to be in the same project
as the apicast (of course, unless you are using a flat network...).

In an OpenShift environment, the `SYSLOG_HOST` would look like:
```
<service-name>.<project>.svc.cluster.local
```

**WARNING:** You cannot use a short name (ie `syslog-ng`). It has to be a FQDN.
This is because nginx does not rely on the standard glibc API `gethostbyname` but
uses instead a custom resolver.

Once, you get it to work on `apicast-staging`, you can do the same on `apicast-production`.

## Performances

The following section tries to evaluate the overhead of this module on apicast
performances.

Performance tests have been run on a vanilla apicast 3.0 and an apicast with this
module. Both tests have been run with 1k requests and responses and 10k requests
and responses.

All tests have been performed on the same hardware :
 - Macbook Pro 15" Mid-2015
 - 2,5 GHz Intel Core i7 (8 cores)
 - 16 GB of RAM

All components apicast + rsyslog ran on the same machine, directly on MacOS.
All external systems (3scale backend, Echo API) have been simulated using
the apicast built-in stubs.


More information is available [here](performance-testing).

The results are the following:

| test | req / s | overhead |
| --- | --- | --- |
| 1K Request + Response - Vanilla | 7692 | - |
| 1K Request + Response - with this module | 5882 | **- 23%** |
| 10K Request + Response - Vanilla | 6250 | - |
| 10K Request + Response - with this module | 3174 | **- 49%** |

The results are not very surprising considering that the module needs to:
 - read the full body of the request and the response
 - encode them as base64
 - serialize the whole data as JSON

**TODO:** run performance tests to analyze the added latency

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

## Configuration

The following excerpt shows a sample configuration for this module, when used
as a service policy.

```javascript
{
  "services":[
    {
      "id":42,
      "proxy":{
        "policy_chain":[
          {
            "name":"custom.logger.verbose",       // the verbose policy that lays in the ./gateway/custom/logger/ directory
            "configuration": {
              "syslog_host": "syslog.acme.test",  // the hostname of the syslog server
              "syslog_port": 1601,                // the port of the syslog server
              "syslog_protocol": "tcp",           // the protocol to use to connect to the syslog server (tcp or udp)
              "syslog_flush_limit": "0",          // the minimum number of bytes in the buffer before sending logs to the syslog server
              "syslog_drop_limit": "1048576",     // the maximum number of bytes in the buffer before starting to drop messages
              "syslog_periodic_flush": "5",       // the number of seconds between each log flush (0 to disable)
              "payload_encoding": "base64"        // the algorithm used to encode the payload ('base64' or 'none')
            }
          },
          {
            "name":"apicast.policy.apicast"       // also keep the default apicast behavior
          }
        ]
      }
    }
  ]
}
```

## Development

First of all, setup your development environment as explained [here](https://github.com/3scale/apicast/tree/master#development--testing).

Then, issue the following commands:
```
git clone https://github.com/nmasse-itix/apicast-logger.git
git clone https://github.com/3scale/apicast.git
git clone https://github.com/cloudflare/lua-resty-logger-socket.git
export GIT_ROOT=$PWD
cd apicast
luarocks make apicast/*.rockspec --local
mkdir gateway/src/custom
ln -s $GIT_ROOT/apicast-logger/ gateway/src/custom/logger/
cd gateway/src/resty
ln -s $GIT_ROOT/lua-resty-logger-socket/lib/resty/logger/ logger
cd -
```

Configure your apicast with a local configuration:
```
export THREESCALE_CONFIG_FILE=$GIT_ROOT/apicast-logger/config.json
export APICAST_LOG_LEVEL=debug
```

Finally, launch apicast:
```
bin/apicast --dev
```

And in another terminal, launch netcat so that you can simulate a syslog server:
```
nc -l 1601
```

## References

The following reading is recommended if you plan to develop on this module:
 - [How to develop policies for Apicast](https://github.com/3scale/apicast/blob/master/doc/policies.md)

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
