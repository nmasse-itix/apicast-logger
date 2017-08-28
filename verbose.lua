local apicast = require('apicast').new()
local cjson = require('cjson')
local logger = require("resty.logger.socket")

local _M = { _VERSION = '0.0' }
local mt = { __index = setmetatable(_M, { __index = apicast }) }

function _M.new()
  return setmetatable({}, mt)
end

function _M:init()
  local host = os.getenv('SYSLOG_HOST')
  local port = os.getenv('SYSLOG_PORT')
  local proto = os.getenv('SYSLOG_PROTOCOL') or 'tcp'
  local flush_limit = os.getenv('SYSLOG_FLUSH_LIMIT') or '0'
  local drop_limit = os.getenv('SYSLOG_DROP_LIMIT') or '1048576'

  if (host == nil or host == "") then
    ngx.log(ngx.ERR, "The environment SYSLOG_HOST is NOT defined !")
  end

  if (port == nil or port == "") then
    ngx.log(ngx.ERR, "The environment SYSLOG_PORT is NOT defined !")
  end

  port = tonumber(port)
  flush_limit = tonumber(flush_limit)
  drop_limit = tonumber(drop_limit)
  ngx.log(ngx.WARN, "Sending custom logs to " .. proto .. "://" .. host .. ":" .. port .. " with flush_limit = " .. flush_limit .. " and drop_limit = " .. drop_limit)

  if not logger.initted() then
      local ok, err = logger.init{
          host = host,
          port = port,
          sock_type = proto,
          flush_limit = flush_limit,
          drop_limit = drop_limit,
      }
      if not ok then
          ngx.log(ngx.ERR, "failed to initialize the logger: ", err)
      end
  end

  return apicast:init()
end


function do_log(payload)
  -- construct the custom access log message in
  -- the Lua variable "msg"
  local bytes, err = logger.log(payload)
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
      request["body"] = ngx.encode_base64(ngx.var.request_body)
    end
    request["headers"] = ngx.req.get_headers()
    request["start_time"] = ngx.req.start_time()
    request["http_version"] = ngx.req.http_version()
    request["raw"] = ngx.encode_base64(ngx.req.raw_header())
    request["method"] = ngx.req.get_method()
    request["uri_args"] = ngx.req.get_uri_args()
    request["request_id"] = ngx.var.request_id
    dict["request"] = request

    -- Gather information of the response
    local response = {}
    if ngx.ctx.buffered then
      response["body"] = ngx.encode_base64(ngx.ctx.buffered)
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
