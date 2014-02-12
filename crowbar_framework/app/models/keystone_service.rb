# Copyright 2011, Dell 
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class KeystoneService < ServiceObject

  def initialize(thelogger)
    super(thelogger)
    @bc_name = "keystone"
  end
# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "database", "inst" => role.default_attributes["keystone"]["database_instance"] }
    if role.default_attributes[@bc_name]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes[@bc_name]["git_instance"] }
    end
    answer
  end

  def create_proposal
    base = super

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }

    base["attributes"][@bc_name]["git_instance"] = find_dep_proposal("git", true)
    base["attributes"][@bc_name]["database_instance"] = find_dep_proposal("database")

    if nodes.size >= 1
      controller = nodes.find { |n| n.intended_role == "controller" } || nodes.first
      base["deployment"]["keystone"]["elements"] = {
        "keystone-server" => [ controller[:fqdn] ]
      }
    end


    base["attributes"][@bc_name][:service][:token] = '%012d' % rand(1e12)
    base["attributes"][@bc_name][:db][:password]   = random_password

    base
  end

  def validate_proposal_after_save proposal
    validate_at_least_n_for_role proposal, "keystone-server", 1

    if proposal["attributes"][@bc_name]["use_gitrepo"]
      validate_dep_proposal_is_active "git", proposal["attributes"][@bc_name]["git_instance"]
    end

    unless proposal["attributes"][@bc_name][:db][:password]
      validation_error "Password for DB keystone user missing"
    end

    super
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Keystone apply_role_pre_chef_call: entering #{all_nodes.inspect}")

    unless all_nodes.empty?
      tnodes = role.override_attributes["keystone"]["elements"]["keystone-server"]
      unless tnodes.nil?
        net_svc = NetworkService.new @logger
        tnodes.each do |n|
          net_svc.allocate_ip "default", "public", "host", n
        end

        # Virtual floating IPs
        n = NodeObject.find_node_by_name tnodes.first
        service_name = role.name
        domain = n[:domain]
        net_svc.allocate_virtual_ip "default", "admin",  "host", "#{service_name}.#{domain}"
        net_svc.allocate_virtual_ip "default", "public", "host", "#{service_name}.#{domain}"
      end
    end

    @logger.debug("Keystone apply_role_pre_chef_call: leaving")
  end

end

