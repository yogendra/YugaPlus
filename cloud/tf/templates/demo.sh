#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_DIR=$(cd $SCRIPT_DIR/..; pwd)
SCRIPT=$0

[[ -f $SCRIPT_DIR/demo-env ]] && source $SCRIPT_DIR/demo-env

function _help(){
  cat <<EOF
YugabyteDB Demo - YugaPlus
$SCRIPT <COMMANDS> [parameters...]

COMAMNDS
  init     - initial setup
  shell-setup - Setup Bash shell
  db-install - Install database binaries
  db-start - Starts database
  db-configure - configures database
  db-prepare-geopart - prepare geo partitioning for database
  app-setup - download and build application
  app-start - start application
  search - run search demo
  update - run update demo
EOF
}

function shell-setup(){
  echo export REGION=$REGION >> $HOME/.bashrc
  echo 'export PATH=$HOME/yugabyte/bin:$HOME/yugabyte/postgres/bin:$HOME/yugabyte/tools:$PATH' >> $HOME/.bashrc
  echo 'export PS1="[ $REGION :: \u@\h \W]\$  "' >> $HOME/.bashrc
  echo 'printf "\e]1337;SetBadgeFormat=%s\a" $(echo -n $REGION | base64)' >> $HOME/.bashrc
}

function db-install(){
  mkdir -p $HOME/yugabyte
  curl -sSL https://downloads.yugabyte.com/releases/${YB_VERSION}/yugabyte-${YB_RELEASE}-linux-${YB_ARCH}.tar.gz | tar -C $HOME/yugabyte --strip-component=1 -xz
  $HOME/yugabyte/bin/post_install.sh
}

function db-start(){
  if [[ $NODE_IP -ne $YB_FIRST_NODE ]]
  then
    yugabyted \
      start \
      --advertise_address=$NODE_IP \
      --base_dir=$HOME/yugabyte_base_dir \
      --cloud_location=$YB_LOCATION \
      --fault_tolerance=region \
      --join=$YB_FIRST_NODE
  else
    yugabyted \
      start \
      --advertise_address=$NODE_IP \
      --base_dir=$HOME/yugabyte_base_dir \
      --cloud_location=$YB_LOCATION \
      --fault_tolerance=region
  fi
}

function db-configure(){

  yugabyted configure data_placement --fault_tolerance=region --base_dir=$HOME/yugabyte_base_dir

  yb-admin \
    -init_master_addrs  \
    set_preferred_zones $ZONE_PREFERENCE
}
function db-prepare-geopart(){
  ysqlsh -h $(hostname -I) -f $HOME/sample_apps/YugaPlus/backend/src/main/resources/V2__create_geo_partitioned_user_library.sql
}
# Clone and build app
function app-setup(){
  killall java || echo "No java processes found"
  mkdir -p $HOME/sample_apps
  [[ -d $HOME/sample_apps/YugaPlus ]] && rm -rf $HOME/sample_apps/YugaPlus
  git clone -b $APP_BRANCH https://github.com/YugabyteDB-Samples/YugaPlus.git $HOME/sample_apps/YugaPlus
  ( cd $HOME/sample_apps/YugaPlus/backend;  ./mvnw clean package -DskipTests)
}

# Start Application: optional argument enable_follower_reads
function app-start(){
  if [[ -z $OPENAI_API_KEY ]]; then echo "OPENAI_API_KEY not set, quitting!"; echo 1; fi

  if [ "$1" == "enable_follower_reads" ]; then
      export DB_CONN_INIT_SQL="SET session characteristics as transaction read only;SET yb_read_from_followers = true;"
      echo "Enabling follower reads:"
      echo $DB_CONN_INIT_SQL
  fi

  echo "Connecting to the database node:"
  echo  $DB_URL

  sudo killall java || echo "No running java processes found"


  nohup java -jar $HOME/sample_apps/YugaPlus/target/yugaplus-backend-1.0.0.jar &> /tmp/application.log &
}

function search(){
  http GET :8080/api/movie/search \
    prompt=='A long time ago in a galaxy far, far away...' \
    rank==7 \
    X-Api-Key:superbowl-2024
}
function update(){
  appuser="$REGION@gmail.com"

  http DELETE :8080/api/library/remove/1891 user==$appuser X-Api-Key:superbowl-2024
  http DELETE :8080/api/library/remove/1895 user==$appuser X-Api-Key:superbowl-2024
  http DELETE :8080/api/library/remove/11 user==$appuser X-Api-Key:superbowl-2024

  http PUT :8080/api/library/add/11 user==$appuser X-Api-Key:superbowl-2024
  http PUT :8080/api/library/add/1891 user==$appuser X-Api-Key:superbowl-2024
  http PUT :8080/api/library/add/1895 user==$appuser X-Api-Key:superbowl-2024
}

function init(){
  shell-setup
  db-install
  app-setup
}

OP=${1:-_help}
if [[ $# -gt 1 ]] ; then shift ; fi

$OP "$@"


