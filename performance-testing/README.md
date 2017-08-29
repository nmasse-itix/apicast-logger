# Performance Testing

## Setup

- Download and install [gatling](http://gatling.io/).
- Edit `apicast/conf/nginx.conf` to set `worker_connections` to a much reasonable setting for a development machine
- Launch a development apicast with the following parameters:
```
export APICAST_LOG_LEVEL=crit
export THREESCALE_CONFIG_FILE=config.json
sudo sysctl -w kern.maxfiles=65536
sudo sysctl -w kern.maxfilesperproc=65536
sudo launchctl limit maxfiles 65536 65536
ulimit -n 65536
bin/apicast -i 3600 -m on -w 8 &> apicast.log
```

**WARNING:** On MacOS, you have to run apicast **as root** to be able to push up
the maximum number of open files (`ulimit -n`).

- Install and run a rsyslog server:
```
sudo brew install rsyslog
/usr/local/Cellar/rsyslog/*/sbin/rsyslogd -4 -n -f rsyslog.conf -i "$PWD/rsyslog.pid"
```

## Recording a scenario (OPTIONAL)

Gatling scenario are available in the [performance-testing directory](performance-testing).
However, you can record your own by :

- Launcing the recorder and starting a recording
- Doing a test request through the gatling proxy
```
export http_proxy=http://localhost:8000
curl "http://localhost:8080/?user_key=secret" -D - -X POST -d "data"
```

Then, you can customize the scenario to loop over the request you recorded and
add virtual users.

## Running a scenario against the vanilla apicast

Run the gatling scenario:
```
gatling.sh -sf . -s itix.Apicast1kPOST
```

## Running a scenario against the apicast with the logging module

Then, re-start apicast with the following environment:
```
export APICAST_MODULE=custom/verbose
export SYSLOG_HOST=127.0.0.1.xip.io
export SYSLOG_PORT=1601
export SYSLOG_PROTO=tcp
export SYSLOG_PERIODIC_FLUSH=5
export SYSLOG_FLUSH_LIMIT=10240
```

Run the gatling scenario:
```
gatling.sh -sf . -s itix.Apicast1kPOST
```

Check that you have exactly 200000 lines in both `apicast.log`:
- the one created by the apicast server
- the one created by the rsyslog server

```
$ wc -l apicast.log
  200000 apicast.log
```

## Reference

- https://www.digitalocean.com/community/tutorials/how-to-optimize-nginx-configuration
- http://blog.martinfjordvald.com/2011/04/optimizing-nginx-for-high-traffic-loads/
- http://gatling.io/docs/current/general/simulation_setup/#injection
- http://gatling.io/docs/current/cheat-sheet/
- https://superuser.com/a/867865
