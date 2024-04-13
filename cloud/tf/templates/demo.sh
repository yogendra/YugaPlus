#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_DIR=$(cd $SCRIPT_DIR/..; pwd)
SCRIPT_NAME=$(basename $0)
SCRIPT_ENV=$SCRIPT_DIR/$SCRIPT_NAME.env
SCRIPT=$0
YB_HOME=$HOME/yugabyte

[[ -f $SCRIPT_ENV ]] && source $SCRIPT_ENV

APP_ROOT_DIR=$HOME/sample_apps/${APP_MACHINE_NAME}

function _help(){
  cat <<EOF
$APP_NAME
$SCRIPT <COMMANDS> [parameters...]

CONFIG COMMANDS

  app-setup
      download and build application
  app-start
      start application
  app-stop
      stop application
  boot
      initial setup - Start db and app
  shell-setup
      Setup Bash shell
  db-configure
      configures database
  db-install
      Install database binaries
  db-prepare-geopart
      prepare geo partitioning for database
  db-start
      Starts database
  db-stop
      Starts database
  run-on <node-ip>
      run command on a remote node
  run-on-all
      run command on all nodes
  self-update
      run self update
  shell
      create a demo shell

DEMO COMMANDS

  search
      run search demo
  update
      run update demo
EOF
}

function self-update(){
  curl -sSL https://raw.githubusercontent.com/$GITHUB_REPO/$GIT_BRANCH/cloud/tf/templates/demo.sh -o $SCRIPT.new
  chmod 700 $SCRIPT.new
  mv $SCRIPT.new $SCRIPT
}
function shell-setup(){
  echo export REGION_NAME=$REGION_NAME >> $HOME/.bashrc
  echo export YB_HOME=$YB_HOME >> $HOME/.bashrc
  echo 'export PATH=$YB_HOME/bin:$YB_HOME/postgres/bin:$YB_HOME/tools:$PATH' >> $HOME/.bashrc
  echo 'export PS1='"'"'\[\e[38;5;202;48;5;55m\] \[\e[1m\]${REGION_NAME}\[\e[22m\] \[\e[38;5;55;48;5;202m\] \w \[\e[0m\] \$ '"'"'' >> $HOME/.bashrc
  echo 'printf "\e]1337;SetBadgeFormat=%s\a" $(echo -n $REGION_NAME | base64)' >> $HOME/.bashrc
}

function shell(){
  tmux kill-session -t demo &>> /dev/null || echo "No running shell"

  tmux new-session -d -s demo -n admin "ssh -i $HOME/.ssh/id_rsa -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@${YB_NODES[0]}"
  tmux split-window -t demo:admin -p 66  "ssh -i $HOME/.ssh/id_rsa -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@${YB_NODES[1]}"
  tmux split-window -t demo:admin -p 50  "ssh -i $HOME/.ssh/id_rsa -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@${YB_NODES[2]}"
  tmux synchronize-panes -t demo:admin

  tmux new-window -a -t demo:admin -n local  "$HOME/yugabyte/bin/ysqlsh -h $NODE_IP"

  tmux new-window -a -t demo:local -n db "ssh -i $HOME/.ssh/id_rsa -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@${YB_NODES[0]}"

  tmux select-window -t demo:shell
  tmux attach-session -t demo
}

function db-install(){
  mkdir -p $YB_HOME
  curl -sSL https://downloads.yugabyte.com/releases/${YB_VERSION}/yugabyte-${YB_RELEASE}-linux-${YB_ARCH}.tar.gz | tar -C $YB_HOME --strip-component=1 -xz
  $YB_HOME/bin/post_install.sh
}
function _db_wait(){
  db=$1; shift

  echo -n  "Wait for ${db} to be up ."
  until $YB_HOME/postgres/bin/pg_isready -h $db &> /dev/null;
  do
    echo -n "."
    sleep $((1 + $RANDOM % 10))
  done
  echo " Ready"
}
function db-start(){
  if [[ $YB_FIRST_NODE == $NODE_IP  ]]
  then
    $YB_HOME/bin/yugabyted \
      start \
      --advertise_address=$NODE_IP \
      --cloud_location=$YB_LOCATION \
      --fault_tolerance=region
  else

    _db_wait $YB_FIRST_NODE
    echo -n "Wait for all existing masters to be ready "
    while [[ $($YB_HOME/bin/yb-admin -init_master_addrs $YB_FIRST_NODE  list_all_masters json | grep -v ^Master | grep -vE '(LEADER|FOLLOWER)' | wc -l) -gt 0 ]] ; do
      echo -n "."
      sleep $((1 + $RANDOM % 10))
    done
    echo " Ready"


    $YB_HOME/bin/yugabyted \
      start \
      --advertise_address=$NODE_IP \
      --cloud_location=$YB_LOCATION \
      --fault_tolerance=region \
      --join=$YB_FIRST_NODE
  fi
}
function db-stop(){
    $YB_HOME/bin/yugabyted \
      stop \
      --advertise_address=$NODE_IP
}
function db-configure(){
  if [[ $YB_FIRST_NODE ==  $NODE_IP  ]]
  then
    for dbnode in "${YB_NODES[@]}"
    do
      if [[ $dbnode != $NODE_IP ]]; then
      _db_wait $dbnode
      fi
    done
    echo "All nodes ready."

    $YB_HOME/bin/yugabyted configure data_placement --fault_tolerance=region

    $YB_HOME/bin/yb-admin \
      -master_addresses $YB_MASTERS \
      set_preferred_zones $ZONE_PREFERENCE

    $YB_HOME/bin/ysqlsh -h $NODE_IP -c 'ALTER ROLE yugabyte SET yb_silence_advisory_locks_not_supported_error=on;'
  else
    echo "Skipping DB configuration as its not the primary node"
  fi
}
function db-shell(){
  $YB_HOME/bin/ysqlsh -h $(hostname -I)
}
function db-prepare-geopart(){
  $YB_HOME/bin/ysqlsh -h $(hostname -I) -f $APP_ROOT_DIR/backend/src/main/resources/V2__create_geo_partitioned_user_library-apj.sql
}
# Clone and build app
function app-setup(){
  app-stop
  [[ -d ${APP_ROOT_DIR} ]] && rm -rf ${APP_ROOT_DIR}
  mkdir -p $APP_ROOT_DIR
  git clone -b $GIT_BRANCH https://github.com/$GITHUB_REPO.git ${APP_ROOT_DIR}
  pushd ${APP_ROOT_DIR}/backend
  mvn clean package -DskipTests
  popd

  pushd ${APP_ROOT_DIR}/frontend
  npm install
  popd
}

# Start Application: optional argument enable_follower_reads
function app-start(){
  if [[ -z $OPENAI_API_KEY ]]; then echo "OPENAI_API_KEY not set, quitting!"; echo 1; fi

  if [ "${1:-x}" == "enable_follower_reads" ]; then
      export DB_CONN_INIT_SQL="SET session characteristics as transaction read only;SET yb_read_from_followers = true;"
      echo "Enabling follower reads:"
      echo $DB_CONN_INIT_SQL
  fi

  echo "Connecting to the database node:"
  echo  $DB_URL

  app-stop

  pushd ${APP_ROOT_DIR}/backend
  nohup java -jar target/*.jar &>> /tmp/app-backend.log &
  popd

  pushd ${APP_ROOT_DIR}/frontend
  nohup npm start &>> /tmp/app-frontend.log &
  popd
}
function app-stop(){
  killall -u yugabyte java &>> /dev/null || echo "No running java processes found"
  killall -u yugabyte node &>> /dev/null || echo "No running java processes found"
}

function search(){
  set -v
  http GET :8080/api/movie/search \
    prompt=='A long time ago in a galaxy far, far away...' \
    rank==7 \
    X-Api-Key:$BACKEND_API_KEY
}
function update(){
  appuser=$1;shift
  set -v

  http DELETE :8080/api/library/remove/1891 user==$appuser X-Api-Key:$BACKEND_API_KEY
  http DELETE :8080/api/library/remove/1895 user==$appuser X-Api-Key:$BACKEND_API_KEY
  http DELETE :8080/api/library/remove/11 user==$appuser X-Api-Key:$BACKEND_API_KEY

  http PUT :8080/api/library/add/11 user==$appuser X-Api-Key:$BACKEND_API_KEY
  http PUT :8080/api/library/add/1891 user==$appuser X-Api-Key:$BACKEND_API_KEY
  http PUT :8080/api/library/add/1895 user==$appuser X-Api-Key:$BACKEND_API_KEY
}
function run-on(){
  node=$1; shift
  if [[ $node == $NODE_IP ]]; then
    echo "$node: Run locally"
    "$@"
  else
    echo "$node: Run remotely"
    ssh -i $HOME/.ssh/id_rsa -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@$node demo "$@"
  fi

}
function run-on-all(){
  for node in "${YB_NODES[@]}"
  do
    run-on $node "$@"
  done
}

function boot(){
  echo Shell Setup
  shell-setup

  echo DB Install
  db-install

  echo DB Start
  db-install

  echo DB Configure
  db-configure

  echo App setup
  app-setup
}

OP=${1:-_help}
if [[ $# -gt 1 ]] ; then shift ; fi

$OP "$@"
