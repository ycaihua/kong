local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local pl_stringx = require "pl.stringx"

describe("#ci Plugin: syslog (log)", function()
  local client, platform
  setup(function()
    assert(helpers.start_kong())

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "logging.com",
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      request_host = "logging2.com",
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      request_host = "logging3.com",
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "syslog",
      config = {
        log_level = "info",
        successful_severity = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning"
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "syslog",
      config = {
        log_level = "err",
        successful_severity = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning"
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "syslog",
      config = {
        log_level = "warning",
        successful_severity = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning"
      }
    })

    local ok, _, stdout = helpers.execute("uname")
    assert(ok, "failed to retrieve platform name")
    platform = pl_stringx.strip(stdout)
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)
  after_each(function()
    if client then client:close() end
  end)

  local function do_test(host, expecting_same)
    local uuid = utils.random_string()

    local response = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = host,
        sys_log_uuid = uuid,
      }
    })
    assert.res_status(200, response)

    if platform == "Darwin" then
      local _, _, stdout = assert(helpers.execute("syslog -k Sender kong | tail -1"))
      local msg = string.match(stdout, "{.*}")
      local json = cjson.decode(msg)

      if expecting_same then
        assert.equal(uuid, json.request.headers["sys-log-uuid"])
      else
        assert.not_equal(uuid, json.request.headers["sys-log-uuid"])
      end
    elseif expecting_same then
      local _, _, stdout = assert(helpers.execute("find /var/log -type f -mmin -5 2>/dev/null | xargs grep -l "..uuid))
      assert.True(#stdout > 0)
    end
  end

  it("logs to syslog if log_level is lower", function()
    do_test("logging.com", true)
  end)
  it("does not log to syslog if log_level is higher", function()
    do_test("logging2.com", false)
  end)
  it("logs to syslog if log_level is the same", function()
    do_test("logging3.com", true)
  end)
end)
