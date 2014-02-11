# Copyright 2014 SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "pacemaker::default"

attrs = node[:pacemaker][:primitives][:keystone]
monitor_creds = node[:keystone][:admin]

proposal_name = node[:keystone][:config][:environment]
domain = node[:domain]

vip_primitives = []
%w(admin public).each do |network|
  net_db = data_bag_item('crowbar', "#{network}_network")
  ip_addr = net_db["allocated_by_name"]["#{proposal_name}.#{domain}"]["address"]

  primitive_name = "#{proposal_name}-#{network}-vip"
  pacemaker_primitive primitive_name do
    agent "ocf:heartbeat:IPaddr2"
    params ({
      "ip" => ip_addr,
    })
    op node[:pacemaker][:primitives][:keystone][:op]
    action :create
  end
  vip_primitives << primitive_name
end

service_name = proposal_name + '-service'
pacemaker_primitive service_name do
  agent attrs[:agent]
  params ({
    "os_auth_url"    => node[:keystone][:api][:versioned_admin_URL],
    "os_tenant_name" => monitor_creds[:tenant],
    "os_username"    => monitor_creds[:username],
    "os_password"    => monitor_creds[:password],
    "user"           => node[:keystone][:user]
  })
  op node[:pacemaker][:primitives][:keystone][:op]
  action :create
end

pacemaker_group "#{proposal_name}-group" do
  # Membership order *is* significant; VIPs should come first so
  # that they are available for the keystone service to bind to.
  members vip_primitives + [service_name]

  meta ({
    "is-managed" => true,
    "target-role" => "started"
  })
  action [ :create, :start ]
end
