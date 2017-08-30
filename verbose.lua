local apicast = require('apicast').new()
local cjson = require('cjson')
local logger = require("resty.logger.socket")

local _M = { _VERSION = '0.0' }
local mt = { __index = setmetatable(_M, { __index = apicast }) }

function _M.new()
  return setmetatable({}, mt)
end

local host
local port
local proto
local flush_limit
local drop_limit

-- Parse and validate the parameters:
--   SYSLOG_HOST => the hostname of the syslog server
--   SYSLOG_PORT => the port of the syslog server
--   SYSLOG_PROTOCOL => the protocol to use to connect to the syslog server (tcp or udp)
--   SYSLOG_FLUSH_LIMIT => the minimum number of bytes in the buffer before sending logs to the syslog server
--   SYSLOG_DROP_LIMIT => the maximum number of bytes in the buffer before starting to drop messages
--   SYSLOG_PERIODIC_FLUSH => the number of seconds between each log flush (0 to disable)
--
function _M:init()
  host = os.getenv('SYSLOG_HOST')
  port = os.getenv('SYSLOG_PORT')
  proto = os.getenv('SYSLOG_PROTOCOL') or 'tcp'
  base64_flag = os.getenv('APICAST_PAYLOAD_BASE64') or 'true'
  flush_limit = os.getenv('SYSLOG_FLUSH_LIMIT') or '0'
  periodic_flush = os.getenv('SYSLOG_PERIODIC_FLUSH') or '5'
  drop_limit = os.getenv('SYSLOG_DROP_LIMIT') or '1048576'

  if (host == nil or host == "") then
    ngx.log(ngx.ERR, "The environment SYSLOG_HOST is NOT defined !")
  end

  if (port == nil or port == "") then
    ngx.log(ngx.ERR, "The environment SYSLOG_PORT is NOT defined !")
  end

  port = tonumber(port)
  flush_limit = tonumber(flush_limit)
  drop_limit = tonumber(drop_limit)
  periodic_flush = tonumber(periodic_flush)

  ngx.log(ngx.WARN, "Sending custom logs to " .. proto .. "://" .. (host or "") .. ":" .. (port or "") .. " with flush_limit = " .. flush_limit .. " bytes, periodic_flush = " .. periodic_flush .. " sec. and drop_limit = " .. drop_limit .. " bytes")

  return apicast:init()
end

-- Initialize the underlying logging module. Since the module calls 'timer_at'
-- during initialization, we need to call it from a init_worker_by_lua block.
--
function _M:init_worker()
  ngx.log(ngx.INFO, "Initializing the underlying logger")
  if not logger.initted() then
      -- default parameters
      local params = {
          host = host,
          port = port,
          sock_type = proto,
          flush_limit = flush_limit,
          drop_limit = drop_limit
      }

      -- periodic_flush == 0 means 'disable this feature'
      if periodic_flush > 0 then
        params["periodic_flush"] = periodic_flush
      end

      -- initialize the logger
      local ok, err = logger.init(params)
      if not ok then
          ngx.log(ngx.ERR, "failed to initialize the logger: ", err)
      end
  end

  return apicast:init_worker()
end


function do_log(payload)
  -- construct the custom access log message in
  -- the Lua variable "msg"
  --
  -- do not forget the \n in order to have one request per line on the syslog server
  --
  local bytes, err = logger.log(payload .. "\n")
  if err then
      ngx.log(ngx.ERR, "failed to log message: ", err)
  end
end

-- This function is called for each chunk of response received from upstream server
-- when the last chunk is received, ngx.arg[2] is true.
function _M.body_filter()
  ngx.ctx.buffered = (ngx.ctx.buffered or "") .. ngx.arg[1]

  if ngx.arg[2] then -- EOF
    local dict = {}

    -- Gather information of the request
    local request = {}
    if ngx.var.request_body then
      if (base64_flag == 'true') then
        request["body"] = ngx.encode_base64(ngx.var.request_body)
      else
        request["body"] = ngx.var.request_body
      end
    end
    request["headers"] = ngx.req.get_headers()
    request["start_time"] = ngx.req.start_time()
    request["http_version"] = ngx.req.http_version()
    if (base64_flag == 'true') then
      request["raw"] = ngx.encode_base64(ngx.req.raw_header())
    else
      request["raw"] = ngx.req.raw_header()
    end

    request["method"] = ngx.req.get_method()
    request["uri_args"] = ngx.req.get_uri_args()
    request["request_id"] = ngx.var.request_id
    dict["request"] = request

    -- Gather information of the response
    local response = {}
    if ngx.ctx.buffered then
      if (base64_flag == 'true') then
        response["body"] = ngx.encode_base64(ngx.ctx.buffered)
      else
        response["body"] = ngx.ctx.buffered
      end
    end
    response["headers"] = ngx.resp.get_headers()
    response["status"] = ngx.status
    dict["response"] = response

    -- timing stats
    local upstream = {}
    upstream["addr"] = ngx.var.upstream_addr
    upstream["bytes_received"] = ngx.var.upstream_bytes_received
    upstream["cache_status"] = ngx.var.upstream_cache_status
    upstream["connect_time"] = ngx.var.upstream_connect_time
    upstream["header_time"] = ngx.var.upstream_header_time
    upstream["response_length"] = ngx.var.upstream_response_length
    upstream["response_time"] = ngx.var.upstream_response_time
    upstream["status"] = ngx.var.upstream_status
    dict["upstream"] = upstream

    do_log(cjson.encode(dict))
  end
  return apicast:body_filter()
end

return _M
