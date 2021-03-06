module(..., lunit.testcase, package.seeall)

local common = dofile("common.lua")
local net = require "luanode.net"
local json = require "json"
local fs = require('luanode.fs')

function test()
local have_openssl

crypto = require ("luanode.crypto")
have_openssl = true
--have_openssl, crypto = pcall(require, "luanode.crypto")
if not have_openssl then
	console.log("Not compiled with OPENSSL support.")
	process:exit()
end

local caPem = fs.readFileSync(common.fixturesDir .. "/test_ca.pem", 'ascii')
local certPem = fs.readFileSync(common.fixturesDir .. "/test_cert.pem", 'ascii')
local keyPem = fs.readFileSync(common.fixturesDir .. "/test_key.pem", 'ascii')

--try{
  local context = crypto.createContext({key=keyPem, cert=certPem, ca=caPem})
--} catch (e) {
--  console.log("Not compiled with OPENSSL support.")
--  process.exit()
--}

local testData = "TEST123"
local serverData = ''
local clientData = ''
local gotSecureServer = false
local gotSecureClient = false

local secureServer = net.createServer(function (self, connection)
	local server = self
	console.log("server got connection: remoteAddress: %s:%s", connection:remoteAddress())
	connection:setSecure(context)
	connection:setEncoding("UTF8")

	connection:addListener("secure", function ()
		gotSecureServer = true
		local verified = connection:verifyPeer()
		local peerDN = connection:getPeerCertificate()
		assert_equal(true, verified)

		assert_equal("/C=UY/ST=Montevideo/L=Montevideo/O=LuaNode/CN=Ignacio Burgueno/emailAddress=iburgueno@gmail.com", peerDN.subject)
		assert_equal("/C=UY/ST=Montevideo/O=LuaNode/CN=Ignacio Burgueno/emailAddress=iburgueno@gmail.com", peerDN.issuer)

		assert_equal("Nov  9 15:44:54 2010 GMT", peerDN.valid_from)
		assert_equal("Nov  9 15:44:54 2011 GMT", peerDN.valid_to)	-- should extend this
		
		assert_equal("A1:2F:6E:F0:DE:10:CB:CC:2E:DC:4A:31:AC:F7:B6:9D:E3:98:B5:58", peerDN.fingerprint)
	end)

	connection:addListener("data", function (self, chunk)
		serverData = serverData .. chunk
		connection:write(chunk)
	end)

	connection:addListener("end", function ()
		assert_equal(serverData, testData)
		connection:finish()
		server:close()
	end)
end)
secureServer:listen(common.PORT)

secureServer:addListener("listening", function()
	local secureClient = net.createConnection(common.PORT)

	secureClient:setEncoding("UTF8")
	secureClient:addListener("connect", function ()
		secureClient:setSecure(context)
	end)

	secureClient:addListener("secure", function ()
		gotSecureClient = true
		local verified = secureClient:verifyPeer()
		local peerDN = secureClient:getPeerCertificate()
		assert_equal(true, verified)
		assert_equal("/C=UY/ST=Montevideo/L=Montevideo/O=LuaNode/CN=Ignacio Burgueno/emailAddress=iburgueno@gmail.com", peerDN.subject)
		assert_equal("/C=UY/ST=Montevideo/O=LuaNode/CN=Ignacio Burgueno/emailAddress=iburgueno@gmail.com", peerDN.issuer)

		assert_equal("Nov  9 15:44:54 2010 GMT", peerDN.valid_from)
		assert_equal("Nov  9 15:44:54 2011 GMT", peerDN.valid_to)	-- should extend this
		assert_equal("A1:2F:6E:F0:DE:10:CB:CC:2E:DC:4A:31:AC:F7:B6:9D:E3:98:B5:58", peerDN.fingerprint)

		secureClient:write(testData)
		secureClient:finish()
	end)

	secureClient:addListener("data", function (self, chunk)
		clientData = clientData .. chunk
	end)

	secureClient:addListener("end", function ()
		assert_equal(clientData, testData)
	end)
end)

process:addListener("exit", function ()
	assert_true(gotSecureServer, "Did not get secure event for server")
	assert_true(gotSecureClient, "Did not get secure event for client")
end)


process:loop()
end