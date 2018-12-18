#! /usr/bin/python


__author__ = 'Cam Maxwell'
import argparse
import requests
import string
import random
import time

start = time.time()

parser = argparse.ArgumentParser(description='Generates and requests random URLs')
parser.add_argument('-u', '--base_url', required=True, help='Base URL for testing')
parser.add_argument('-c', '--request_count', required=True, help='Number of requests to send')

args = parser.parse_args()
base_url = args.base_url
request_count = args.request_count
# responses = {}
if base_url and request_count:
	i = 0
	denied=0
	while i < request_count:
		extra_string = ''.join(random.choice(string.lowercase + string.digits) for _ in range(12))
		try:
			r = requests.get(base_url + extra_string)
		except:
			print "Connection error"
			continue
		status_code = str(r.status_code)
		print(base_url + extra_string + ': ' + status_code)
		if(status_code=='403'):
			end = time.time()
			print ("We were blocked in " +str(int(end - start)) + " seconds!")
			break		
		# if status_code in responses:
		# 	responses[status_code] += 1
		# else:
		# 	responses[status_code] = 1
		# i += 1

