#!/usr/bin/python
#coding:utf-8

try: import httplib
except ImportError:
    import http.client as httplib
import sys
import urllib
import urllib2
import time
import json
import itertools
import mimetypes
import base64
import hmac
import uuid
from hashlib import sha1


class AliyunMonitor:
    def __init__(self,url):
        self.access_id = 'your-access-id'
        self.access_secret = 'your-access-secret'
        self.url = url

    ##签名
    def sign(self,accessKeySecret, parameters):
        sortedParameters = sorted(parameters.items(), key=lambda parameters: parameters[0])
        canonicalizedQueryString = ''
        for (k,v) in sortedParameters:
            canonicalizedQueryString += '&' + self.percent_encode(k) + '=' + self.percent_encode(v)

        stringToSign = 'GET&%2F&' + self.percent_encode(canonicalizedQueryString[1:]) #使用get请求方法

        h = hmac.new(accessKeySecret + "&", stringToSign, sha1)
        signature = base64.encodestring(h.digest()).strip()
        return signature

    def percent_encode(self,encodeStr):
        encodeStr = str(encodeStr)
        res = urllib.quote(encodeStr.decode(sys.stdin.encoding).encode('utf8'), '')
        res = res.replace('+', '%20')
        res = res.replace('*', '%2A')
        res = res.replace('%7E', '~')
        return res

    def make_url(self,params):
        timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        parameters = {
            'Format' : 'JSON',
            'Version' : '2014-05-26',
            'AccessKeyId' : self.access_id,
            'SignatureVersion' : '1.0',
            'SignatureMethod' : 'HMAC-SHA1',
            'SignatureNonce' : str(uuid.uuid1()),
            'TimeStamp' : timestamp,
        }
        for key in params.keys():
            parameters[key] = params[key]

        signature = self.sign(self.access_secret,parameters)
        parameters['Signature'] = signature
        url = self.url + "/?" + urllib.urlencode(parameters)
        return url

    def do_request(self,params):
        url = self.make_url(params)
        #print(url)
        request = urllib2.Request(url)
        try:
            conn = urllib2.urlopen(request)
            response = conn.read()
        except urllib2.HTTPError, e:
            print(e.read().strip())
            raise SystemExit(e)
        try:
            obj = json.loads(response)
        except ValueError, e:
            raise SystemExit(e)
        return obj

    def create_instance(self, RegionId = "cn-beijing", ImageId = "ubuntu1404_64_40G_cloudinit_20160727.raw", InstanceType = "ecs.t1.small", SecurityGroupId = "sg-25im5cmy3"):
        self.instance = self.do_request({"Action": "CreateInstance", "RegionId": RegionId, "ImageId": ImageId, "InstanceType": InstanceType, "SecurityGroupId": SecurityGroupId})
        self.regionid = RegionId
        return self.instance["InstanceId"]

    def start_instance(self, InstanceId):
        ret = self.do_request({"Action": "StartInstance", "InstanceId": InstanceId})
        # TODO: return what?

    def check_instance_status(self, InstanceId):
        statuses = self.do_request({"Action": "DescribeInstanceStatus", "RegionId": self.regionid})
        for status in statuses["InstanceStatuses"]["InstanceStatus"]:
            if status["InstanceId"] == InstanceId:
                return status["Status"]


if __name__ == "__main__":
    T = AliyunMonitor("https://ecs.aliyuncs.com")
    '''
    T.do_request({"Action": "DescribeImages", "RegionId": "cn-beijing"})
    # 创建实例
    instance = T.do_request({"Action":"CreateInstance","RegionId":"cn-beijing","ImageId":"ubuntu1404_64_40G_cloudinit_20160727.raw","InstanceType":"ecs.t1.small", "SecurityGroupId": "sg-25im5cmy3"})
    # 启动虚拟机
    start_result = T.do_request({"Action": "StartInstance", "InstanceId": instance["InstanceId"]})

    # 查询实例状态
    statuses = T.do_request({"Action": "DescribeInstanceStatus", "RegionId": "cn-beijing"})
    '''

    instance_id = T.create_instance()
    T.start_instance(instance_id)
    count = 0
    print("当前时间：" + str(time.time()))
    time_start = time.time()
    while True:
        st = T.check_instance_status(instance_id)
        if st != "Running":
            count += 1
            time.sleep(0.1)
        else:
            break
    print("结束时间：" + str(time.time()))
    time_end = time.time()
    print("开始时间：%s, 结束时间：%s, 经过时间：%s" % (time_start, time_end, time_end - time_start))
