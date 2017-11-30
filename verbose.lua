local policy = require('apicast.policy')
local _M = policy.new('Verbose Logger Policy')

local cjson = require('cjson')
local logger = require("resty.logger.socket")

-- Parse and validate the parameters:
--   syslog_host => the hostname of the syslog server
--   syslog_port => the port of the syslog server
--   syslog_protocol => the protocol to use to connect to the syslog server (tcp or udp)
--   syslog_flush_limit => the minimum number of bytes in the buffer before sending logs to the syslog server
--   syslog_drop_limit => the maximum number of bytes in the buffer before starting to drop messages
--   syslog_periodic_flush => the number of seconds between each log flush (0 to disable)
--   payload_encoding => the algorithm used to encode the payload ('base64' or 'none')
--
local new = _M.new
function _M.new(config)
  local self = new()

  -- Optional parameters
  self.proto = config.syslog_protocol or 'tcp'
  self.base64_flag = config.payload_encoding and (config.payload_encoding == 'base64')
  self.flush_limit = config.syslog_flush_limit or 0
  self.periodic_flush = config.syslog_periodic_flush or 5
  self.drop_limit = config.syslog_drop_limit or 1048576

  -- Required parameters
  if (config.syslog_host == nil or config.syslog_host == "") then
    ngx.log(ngx.ERR, "The configuration option syslog_host is NOT defined !")
  end

  if (config.syslog_port == nil or config.syslog_port == "") then
    ngx.log(ngx.ERR, "The configuration option syslog_port is NOT defined !")
  end

  self.host = config.syslog_host
  self.port = tonumber(config.syslog_port)

  ngx.log(ngx.WARN, "Sending custom logs to " .. self.proto .. "://" .. (self.host or "") .. ":" .. (self.port or "") .. " with flush_limit = " .. self.flush_limit .. " bytes, periodic_flush = " .. self.periodic_flush .. " sec. and drop_limit = " .. self.drop_limit .. " bytes")

  return self
end

-- Initialize the underlying logging module. Since the module calls 'timer_at'
-- during initialization, we need to call it from a init_worker_by_lua block.
--
function _M:init_worker()
  ensure_logger_is_initted(self)
end

local function ensure_logger_is_initted(self)
  if not logger.initted() then
    ngx.log(ngx.INFO, "Initializing the underlying logger")
      -- default parameters
      local params = {
          host = self.host,
          port = self.port,
          sock_type = self.proto,
          flush_limit = self.flush_limit,
          drop_limit = self.drop_limit
      }

      -- periodic_flush == 0 means 'disable this feature'
      if self.periodic_flush > 0 then
        params["periodic_flush"] = self.periodic_flush
      end

      -- initialize the logger
      local ok, err = logger.init(params)
      if not ok then
          ngx.log(ngx.ERR, "failed to initialize the logger: ", err)
      end
  end
end

local function do_log(payload)
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
function _M:body_filter(context)
  context.buffered = (context.buffered or "") .. ngx.arg[1]

  if ngx.arg[2] then -- EOF
    local dict = {}

    -- Gather information of the request
    local request = {}
    if ngx.var.request_body then
      if (self.base64_flag) then
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
    if context.buffered then
      if (self.base64_flag) then
        response["body"] = ngx.encode_base64(context.buffered)
      else
        response["body"] = context.buffered
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

    ensure_logger_is_initted(self)
    do_log(cjson.encode(dict))
  end
end

return _M
