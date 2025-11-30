#!/bin/bash
# Configure Wazuh agent
echo "Configuring Wazuh agent..."

# Generate unique agent name
UNIQUE_NAME="honeypot-$(hostname)-$(date +%s)"

# Create basic agent configuration with unique name
cat > /var/ossec/etc/ossec.conf << EOF
<ossec_config>
  <client>
    <server>
      <address>wazuh.manager</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <config-profile>generic</config-profile>
    <notify_time>60</notify_time>
    <time-reconnect>300</time-reconnect>
    <auto_restart>yes</auto_restart>
    <crypto_method>aes</crypto_method>
    <enrollment>
      <enabled>yes</enabled>
      <agent_name>${UNIQUE_NAME}</agent_name>
      <groups>default</groups>
    </enrollment>
  </client>
  <client_buffer>
    <disabled>no</disabled>
    <queue_size>5000</queue_size>
    <events_per_second>500</events_per_second>
  </client_buffer>
  <!-- Rest of your existing config -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>
  <localfile>
    <log_format>command</log_format>
    <command>ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -20</command>
    <frequency>60</frequency>
  </localfile>
  <localfile>
    <log_format>command</log_format>
    <command>netstat -tulpn | grep LISTEN</command>
    <frequency>60</frequency>
  </localfile>
  <localfile>
    <log_format>command</log_format>
    <command>find /tmp /var/tmp -type f -mmin -1 2>/dev/null | head -10</command>
    <frequency>60</frequency>
  </localfile>
</ossec_config>
EOF

echo "Starting Wazuh agent with name: ${UNIQUE_NAME}"
/var/ossec/bin/wazuh-control start

echo "Starting honeypot application..."
exec /docker-gs-ping
