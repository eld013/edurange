# There's a lot of stuff to do here, step by step.

require 'yaml'
#require 'net/ssh'

# Config

EC2_UTILS_PATH = "/home/ubuntu/.ec2/bin/"

ami_id = "ami-e720ad8e"

vm_size = "t1.micro"

key_name = "newkey" # ec2 key name, not file name

puppetmaster_ip = `curl http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null`


#command = "ec2-run-instances #{ami_id} -t #{vm_size} --region us-east-1 --key #{key_name} --user-data-file combined-userdata.txt"
#command = "ec2-run-instances #{ami_id} -t #{vm_size} --region us-east-1 --key #{key_name} -d 'wutloluhh'"

# Spin up some vms


def run(command)
  # runs an ec2 command with full path.
  command = EC2_UTILS_PATH + command
  `#{command}`
end

def get_last_instance_id
  command = 'ec2-describe-instances | grep INSTANCE | tail -n 1'
  vm = run(command)
  return vm.split("\t")[1]
end

class EduMachine
  attr_reader :uuid, :ami_id, :key_name, :vm_size, :ip_address


  def init(key_name, vm_size="t1.micro")
    # generate uuid
    self.uuid = 
    self.instance_id = nil
    self.key_name = key_name
    self.vm_size = vm_size
  end

  def spin_up
    # Pref user-data-file for ourselves

    # Create & run instance, setting instance_id and IP to match the newly created ami
    command = "ec2-run-instances #{self.ami_id} -t #{self.vm_size} --region us-east-1 --key #{self.key_name} --user-data-file my-user-script.sh"
    # run(command)
    self.instance_id = get_last_instance_id()
    self.update_ec2_info()
  end

  def update_ec2_info
    command = "ec2-describe-instances | grep INSTANCE | grep '#{self.instance_id}'"
    vm = run(command).split("\t")
    self.ip_address = vm[17] # public ip
    self.hostname = vm[3] # ec2 hostname
  end
end

def get_our_ssh_key
  # make some ssh keys
  `ssh-keygen -t rsa -f /home/ubuntu/.ssh/id_rsa -N '' -q` unless File.exists?("/home/ubuntu/.ssh/id_rsa")
  # return our public key
  file = File.open("/home/ubuntu/.ssh/id_rsa.pub", "rb")
  contents = file.read
end

def gen_client_ssl_cert
  # We need to:
  # Generate unique name (UUIDgen)
  uuid = `uuidgen`.chomp
  # Create cert for name on puppetmaster
  `sudo puppet cert --generate #{uuid}`
  ssl_cert = `sudo cat /var/lib/puppet/ssl/certs/#{uuid}.pem`.chomp
  ca_cert = `sudo cat /var/lib/puppet/ssl/certs/ca.pem`.chomp
  private_key = `sudo cat /var/lib/puppet/ssl/private_keys/#{uuid}.pem`.chomp
  return [uuid, ssl_cert, ca_cert, private_key]
end

def generate_puppet_conf(uuid)
  conf_file = <<conf
[main]
logdir=/var/log/puppet
vardir=/var/lib/puppet
ssldir=/var/lib/puppet/ssl
rundir=/var/run/puppet
factpath=$vardir/lib/facter
templatedir=$confdir/templates
prerun_command=/etc/puppet/etckeeper-commit-pre
postrun_command=/etc/puppet/etckeeper-commit-post
runinterval=60 # run every minute for debug TODO REMOVE
pluginsync=true

[master]
# These are needed when the puppetmaster is run by passenger
# and can safely be removed if webrick is used.
ssl_client_header = SSL_CLIENT_S_DN 
ssl_client_verify_header = SSL_CLIENT_VERIFY

[agent]
certname=#{uuid}
conf
end

def facter_facts
  facter_conf = <<conf
aaaaaafact=value
conf
end


#def init_crontab
  # set up crontab to refresh list of signable hosts
  # * * * * * ec2-describe-instances | grep ^INSTANCE | grep -v terminated | awk '{print $4}' > /etc/puppet/autosign.conf 
#end

def write_shell_config_file(ssh_key, puppetmaster_ip, certs, puppet_conf, facter_facts)
  File.open("my-user-script.sh", 'w') do |file|
    file_contents = <<contents
#!/bin/sh
set -e
set -x
echo "Hello World.  The time is now $(date -R)!" | tee /root/output.txt
apt-get update; apt-get upgrade -y

key='#{ssh_key.chomp}'
echo $key >> /home/ubuntu/.ssh/authorized_keys

echo #{puppetmaster_ip} puppet >> /etc/hosts
apt-get -y install puppet

mkdir -p /var/lib/puppet/ssl/certs
mkdir -p /var/lib/puppet/ssl/private_keys
mkdir -p /etc/puppet

mkdir -p /etc/facter/facts.d
echo '#{facter_facts}' >> "/etc/facter/facts.d/facts.txt"

echo '#{certs[1]}' >> "/var/lib/puppet/ssl/certs/#{certs[0]}.pem"
echo '#{certs[2]}' >> "/var/lib/puppet/ssl/certs/ca.pem"
echo '#{certs[3]}' >> "/var/lib/puppet/ssl/private_keys/#{certs[0]}.pem"

echo '#{puppet_conf.chomp}' > /etc/puppet/puppet.conf

sed -i /etc/default/puppet -e 's/START=no/START=yes/'
service puppet restart

echo "Goodbye World.  The time is now $(date -R)!" | tee /root/output.txt

contents
    file.write(file_contents)
  end
end

our_ssh_key = get_our_ssh_key()

certs = gen_client_ssl_cert()
conf = generate_puppet_conf(certs[0])

facts = facter_facts()
write_shell_config_file(our_ssh_key,puppetmaster_ip, certs, conf, facts)

run(command)
