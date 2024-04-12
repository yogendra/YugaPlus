# Superbowl Demo: The Art of Scaling

Follow this guide to create a multi-region cluster and see how to achieve low-latency and fault tolerance across distant locations.

NOTE, all the tests were perfomed on commodity hardware in a cloud environment (e2-standard-4). Four vCPUs for each VM.
What is a virtual CPU in Compute Engine? On Compute Engine, each virtual CPU (vCPU) is implemented as a single hardware hyper-thread on one of the available CPU Platforms. This is my sandbox environment for functional experiments. The environment was constrained, non of the components (DB, app, etc.) were optimized.

## Prerequisites

Three VMs with each in one of the following regions - US West, Central and East.

## Configure VMs

Start a VM in the US East, Central and West. The disk size needs to be around 50GB.
You can use a VM image under the following name - **"devrel-superbowl-demo-image"**

Or configure it from scratch:

1. [Download YugabyteDB](https://download.yugabyte.com) binaries to all VMs.
    ```shell
    wget https://downloads.yugabyte.com/releases/2.19.3.0/yugabyte-2.19.3.0-b140-linux-x86_64.tar.gz
    tar xvfz yugabyte-2.19.3.0-b140-linux-x86_64.tar.gz && cd yugabyte-2.19.3.0/
    ./bin/post_install.sh
    ```

2. Create a folder for the YugabyteDB node's config and data:
    ```shell
    rm -r ~/yugabyte_base_dir
    mkdir ~/yugabyte_base_dir
    ```
3. Install distutils:
    ```shell
    sudo apt-get install python3-distutils
    sudo apt-get install python3-apt
    ```
4. Install Java 21+:
    ```shell
    sdk install java 21.0.2-zulu
    ```
5. Clone the app:
    ```shell
    cd $HOME/sample_apps
    git clone https://github.com/YugabyteDB-Samples/YugaPlus.git
    ```
6. Swith to the `superbowl-demo` branch:
    ```shell
    cd YugaPlus
    git fetch
    git switch superbowl-demo
    ```

## Start YugabyteDB Cluster

1. Navigate to the YugabyteDB folder:
    ```shell
    cd $HOME/yugabyte-2.19.3.0/
    ```

2. Deploy a multi-region cluster starting with a node in the US East Coast that will be a preferred region:
    ```shell
    ./bin/yugabyted start --advertise_address=10.142.0.6 \
        --base_dir=~/yugabyte_base_dir \
        --cloud_location=gcp.us-east1.us-east1-b \
        --fault_tolerance=region

    ./bin/yugabyted start --advertise_address=10.128.0.9 \
        --base_dir=~/yugabyte_base_dir \
        --join=10.142.0.6 \
        --cloud_location=gcp.us-central1.us-central1-a \
        --fault_tolerance=region

    ./bin/yugabyted start --advertise_address=10.168.0.6 \
        --base_dir=~/yugabyte_base_dir \
        --join=10.142.0.6 \
        --cloud_location=gcp.us-west2.us-west2-a \
        --fault_tolerance=region
    ```
3. Open the YugabyteDB UI to confirm that nodes are connected: http://35.190.189.43:15433/?tab=tabNodes

After starting the yugabyted processes on all nodes:

1. Configure the data placement constraint of the cluster as follows:
    ```shell
    ./bin/yugabyted configure data_placement --fault_tolerance=region --base_dir=~/yugabyte_base_dir
    ```

2. Make the US East region a [preferred one](https://docs.yugabyte.com/preview/develop/build-global-apps/global-database/#set-preferred-regions):
    ```shell
    ./bin/yb-admin \
        -master_addresses 10.142.0.6:7100,10.128.0.9:7100,10.168.0.6:7100 \
        set_preferred_zones gcp.us-east1.us-east1-b:1 gcp.us-central1.us-central1-a:2 gcp.us-west2.us-west2-a:3
    ```
3. Confirm the prefferred and fallback regions were set: http://35.190.189.43:7000/tablet-servers
    Note, you need to look at the `Leader preference priority:` setting.

## Start Application

Start an application instance on every machine:

1. Build the app:
    ```shell
    cd $HOME/sample_apps/YugaPlus/backend
    mvn clean package -DskipTests
    ```
2. Create a startup script using a template below:
    ```shell
    #!/usr/bin/env bash

    export DB_URL="jdbc:yugabytedb://10.150.0.2:5433/yugabyte"
    export DB_USER=yugabyte
    export DB_PASSWORD=yugabyte
    export DB_DRIVER_CLASS_NAME=com.yugabyte.Driver

    export OPENAI_API_KEY="PUT YOUR KEY HERE"
    export BACKEND_API_KEY=superbowl-2024
    export PORT=8080

    if [ "$1" == "enable_follower_reads" ]; then
        export DB_CONN_INIT_SQL="SET session characteristics as transaction read only;SET yb_read_from_followers = true;"
        echo "Enabling follower reads:"
        echo $DB_CONN_INIT_SQL
    fi

    echo "Connecting to the database node:"
    echo $DB_URL

    sudo killall java

    java -jar target/yugaplus-backend-1.0.0.jar &
    ```

    You can copy a directory with the startup scripts from your local machine as follows:
    ```shell
    scp -i certificates/gcp/gcp-default-key -r ~/Downloads/sample_projects/YugaPlus/env/ dmagda@35.190.189.43:/home/dmagda/sample_apps/YugaPlus/backend
    ```

    and give permissions:
    ```shell
    sudo chmod 744 -R env/
    ```
3. Start the app:
    ```shell
    ./us-east-app-start.sh
    ```

## Testing Read Latency

Compare the read latency by executing various requests from all VMs.

### All VMs Connected to US East YugabyteDB Node

```shell
http GET :8080/api/movie/search prompt=='A long time ago in a galaxy far, far away...' rank==7 X-Api-Key:superbowl-2024
```

The latency will be lowest for the US East which is a preferred region.
For other VMs it just takes much more time to transfer a **significant** paylod of data over the cross-region network!

US East:
```json
{
    "movies": [
        {
            "id": 1891,
            "overview": "The epic saga continues as Luke Skywalker, in hopes of defeating the evil Galactic Empire, learns the ways of the Jedi from aging master Yoda. But Darth Vader is more determined than ever to capture Luke. Meanwhile, rebel leader Princess Leia, cocky Han Solo, Chewbacca, and droids C-3PO and R2-D2 are thrown into various stages of capture, betrayal and despair.",
            "popularity": null,
            "releaseDate": "1980-05-17",
            "title": "The Empire Strikes Back",
            "voteAverage": 8.2,
            "voteCount": null
        },
        {
            "id": 1895,
            "overview": "Years after the onset of the Clone Wars, the noble Jedi Knights lead a massive clone army into a galaxy-wide battle against the Separatists. When the sinister Sith unveil a thousand-year-old plot to rule the galaxy, the Republic crumbles and from its ashes rises the evil Galactic Empire. Jedi hero Anakin Skywalker is seduced by the dark side of the Force to become the Emperor's new apprentice – Darth Vader. The Jedi are decimated, as Obi-Wan Kenobi and Jedi Master Yoda are forced into hiding. The only hope for the galaxy are Anakin's own offspring – the twin children born in secrecy who will grow up to become heroes.",
            "popularity": null,
            "releaseDate": "2005-05-17",
            "title": "Star Wars: Episode III - Revenge of the Sith",
            "voteAverage": 7.1,
            "voteCount": null
        },
        {
            "id": 11,
            "overview": "Princess Leia is captured and held hostage by the evil Imperial forces in their effort to take over the galactic Empire. Venturesome Luke Skywalker and dashing captain Han Solo team together with the loveable robot duo R2-D2 and C-3PO to rescue the beautiful princess and restore peace and justice in the Empire.",
            "popularity": null,
            "releaseDate": "1977-05-25",
            "title": "Star Wars",
            "voteAverage": 8.1,
            "voteCount": null
        }
    ],
    "status": {
        "code": 200,
        "message": "latency is 0.012 seconds",
        "success": true
    }
}
```

US Central:
```json
{
    "movies": [
        {
            "id": 1891,
            "overview": "The epic saga continues as Luke Skywalker, in hopes of defeating the evil Galactic Empire, learns the ways of the Jedi from aging master Yoda. But Darth Vader is more determined than ever to capture Luke. Meanwhile, rebel leader Princess Leia, cocky Han Solo, Chewbacca, and droids C-3PO and R2-D2 are thrown into various stages of capture, betrayal and despair.",
            "popularity": null,
            "releaseDate": "1980-05-17",
            "title": "The Empire Strikes Back",
            "voteAverage": 8.2,
            "voteCount": null
        },
        {
            "id": 1895,
            "overview": "Years after the onset of the Clone Wars, the noble Jedi Knights lead a massive clone army into a galaxy-wide battle against the Separatists. When the sinister Sith unveil a thousand-year-old plot to rule the galaxy, the Republic crumbles and from its ashes rises the evil Galactic Empire. Jedi hero Anakin Skywalker is seduced by the dark side of the Force to become the Emperor's new apprentice – Darth Vader. The Jedi are decimated, as Obi-Wan Kenobi and Jedi Master Yoda are forced into hiding. The only hope for the galaxy are Anakin's own offspring – the twin children born in secrecy who will grow up to become heroes.",
            "popularity": null,
            "releaseDate": "2005-05-17",
            "title": "Star Wars: Episode III - Revenge of the Sith",
            "voteAverage": 7.1,
            "voteCount": null
        },
        {
            "id": 11,
            "overview": "Princess Leia is captured and held hostage by the evil Imperial forces in their effort to take over the galactic Empire. Venturesome Luke Skywalker and dashing captain Han Solo team together with the loveable robot duo R2-D2 and C-3PO to rescue the beautiful princess and restore peace and justice in the Empire.",
            "popularity": null,
            "releaseDate": "1977-05-25",
            "title": "Star Wars",
            "voteAverage": 8.1,
            "voteCount": null
        }
    ],
    "status": {
        "code": 200,
        "message": "latency is 0.137 seconds",
        "success": true
    }
}
```

US West:
```json
{
    "movies": [
        {
            "id": 1891,
            "overview": "The epic saga continues as Luke Skywalker, in hopes of defeating the evil Galactic Empire, learns the ways of the Jedi from aging master Yoda. But Darth Vader is more determined than ever to capture Luke. Meanwhile, rebel leader Princess Leia, cocky Han Solo, Chewbacca, and droids C-3PO and R2-D2 are thrown into various stages of capture, betrayal and despair.",
            "popularity": null,
            "releaseDate": "1980-05-17",
            "title": "The Empire Strikes Back",
            "voteAverage": 8.2,
            "voteCount": null
        },
        {
            "id": 1895,
            "overview": "Years after the onset of the Clone Wars, the noble Jedi Knights lead a massive clone army into a galaxy-wide battle against the Separatists. When the sinister Sith unveil a thousand-year-old plot to rule the galaxy, the Republic crumbles and from its ashes rises the evil Galactic Empire. Jedi hero Anakin Skywalker is seduced by the dark side of the Force to become the Emperor's new apprentice – Darth Vader. The Jedi are decimated, as Obi-Wan Kenobi and Jedi Master Yoda are forced into hiding. The only hope for the galaxy are Anakin's own offspring – the twin children born in secrecy who will grow up to become heroes.",
            "popularity": null,
            "releaseDate": "2005-05-17",
            "title": "Star Wars: Episode III - Revenge of the Sith",
            "voteAverage": 7.1,
            "voteCount": null
        },
        {
            "id": 11,
            "overview": "Princess Leia is captured and held hostage by the evil Imperial forces in their effort to take over the galactic Empire. Venturesome Luke Skywalker and dashing captain Han Solo team together with the loveable robot duo R2-D2 and C-3PO to rescue the beautiful princess and restore peace and justice in the Empire.",
            "popularity": null,
            "releaseDate": "1977-05-25",
            "title": "Star Wars",
            "voteAverage": 8.1,
            "voteCount": null
        }
    ],
    "status": {
        "code": 200,
        "message": "latency is 0.249 seconds",
        "success": true
    }
}
```

### Follower Reads

```shell
http GET :8080/api/movie/search prompt=='A long time ago in a galaxy far, far away...' rank==7 X-Api-Key:superbowl-2024
```

*US Eeast - remains unchanged.*

On US Central and West VMs, connect to the cluster nodes from the same region and use follower reads.
```shell
./us-central-app-start.sh enable_follower_reads

./us-west-app-start.sh enable_follower_reads
```

US Central:
```json
{
    "movies": [
        {
            "id": 1891,
            "overview": "The epic saga continues as Luke Skywalker, in hopes of defeating the evil Galactic Empire, learns the ways of the Jedi from aging master Yoda. But Darth Vader is more determined than ever to capture Luke. Meanwhile, rebel leader Princess Leia, cocky Han Solo, Chewbacca, and droids C-3PO and R2-D2 are thrown into various stages of capture, betrayal and despair.",
            "popularity": null,
            "releaseDate": "1980-05-17",
            "title": "The Empire Strikes Back",
            "voteAverage": 8.2,
            "voteCount": null
        },
        {
            "id": 1895,
            "overview": "Years after the onset of the Clone Wars, the noble Jedi Knights lead a massive clone army into a galaxy-wide battle against the Separatists. When the sinister Sith unveil a thousand-year-old plot to rule the galaxy, the Republic crumbles and from its ashes rises the evil Galactic Empire. Jedi hero Anakin Skywalker is seduced by the dark side of the Force to become the Emperor's new apprentice – Darth Vader. The Jedi are decimated, as Obi-Wan Kenobi and Jedi Master Yoda are forced into hiding. The only hope for the galaxy are Anakin's own offspring – the twin children born in secrecy who will grow up to become heroes.",
            "popularity": null,
            "releaseDate": "2005-05-17",
            "title": "Star Wars: Episode III - Revenge of the Sith",
            "voteAverage": 7.1,
            "voteCount": null
        },
        {
            "id": 11,
            "overview": "Princess Leia is captured and held hostage by the evil Imperial forces in their effort to take over the galactic Empire. Venturesome Luke Skywalker and dashing captain Han Solo team together with the loveable robot duo R2-D2 and C-3PO to rescue the beautiful princess and restore peace and justice in the Empire.",
            "popularity": null,
            "releaseDate": "1977-05-25",
            "title": "Star Wars",
            "voteAverage": 8.1,
            "voteCount": null
        }
    ],
    "status": {
        "code": 200,
        "message": "latency is 0.013 seconds",
        "success": true
    }
}
```

US West:
```json
{
    "movies": [
        {
            "id": 1891,
            "overview": "The epic saga continues as Luke Skywalker, in hopes of defeating the evil Galactic Empire, learns the ways of the Jedi from aging master Yoda. But Darth Vader is more determined than ever to capture Luke. Meanwhile, rebel leader Princess Leia, cocky Han Solo, Chewbacca, and droids C-3PO and R2-D2 are thrown into various stages of capture, betrayal and despair.",
            "popularity": null,
            "releaseDate": "1980-05-17",
            "title": "The Empire Strikes Back",
            "voteAverage": 8.2,
            "voteCount": null
        },
        {
            "id": 1895,
            "overview": "Years after the onset of the Clone Wars, the noble Jedi Knights lead a massive clone army into a galaxy-wide battle against the Separatists. When the sinister Sith unveil a thousand-year-old plot to rule the galaxy, the Republic crumbles and from its ashes rises the evil Galactic Empire. Jedi hero Anakin Skywalker is seduced by the dark side of the Force to become the Emperor's new apprentice – Darth Vader. The Jedi are decimated, as Obi-Wan Kenobi and Jedi Master Yoda are forced into hiding. The only hope for the galaxy are Anakin's own offspring – the twin children born in secrecy who will grow up to become heroes.",
            "popularity": null,
            "releaseDate": "2005-05-17",
            "title": "Star Wars: Episode III - Revenge of the Sith",
            "voteAverage": 7.1,
            "voteCount": null
        },
        {
            "id": 11,
            "overview": "Princess Leia is captured and held hostage by the evil Imperial forces in their effort to take over the galactic Empire. Venturesome Luke Skywalker and dashing captain Han Solo team together with the loveable robot duo R2-D2 and C-3PO to rescue the beautiful princess and restore peace and justice in the Empire.",
            "popularity": null,
            "releaseDate": "1977-05-25",
            "title": "Star Wars",
            "voteAverage": 8.1,
            "voteCount": null
        }
    ],
    "status": {
        "code": 200,
        "message": "latency is 0.012 seconds",
        "success": true
    }
}
```

## Testing Write Latency

Show the write latency for scenarious when a user wants to add a movie to the watch list.

All VMs connected to a node from their own region **without** follower reads:

```shell
http DELETE :8080/api/library/remove/1891 user==user1@gmail.com X-Api-Key:superbowl-2024
http DELETE :8080/api/library/remove/1895 user==user1@gmail.com X-Api-Key:superbowl-2024
http DELETE :8080/api/library/remove/11 user==user1@gmail.com X-Api-Key:superbowl-2024

http PUT :8080/api/library/add/11 user==user1@gmail.com X-Api-Key:superbowl-2024
http PUT :8080/api/library/add/1891 user==user1@gmail.com X-Api-Key:superbowl-2024
http PUT :8080/api/library/add/1895 user==user1@gmail.com X-Api-Key:superbowl-2024
```

The `user1@gmail.com` is for the user living in New York (East). Replace with the following if want to update the library for users from other locations:

* `user2@gmail.com` - Chicago (Central).
* `user3@gmail.com` - Los Angeles (West).

US East Client:
```json
{
    "movies": null,
    "status": {
        "code": 200,
        "message": "latency is 0.071 seconds",
        "success": true
    }
}
```

US Central Client:
```json
{
    "movies": null,
    "status": {
        "code": 200,
        "message": "latency is 0.103 seconds",
        "success": true
    }
}
```

US West Client:
```json
{
    "movies": null,
    "status": {
        "code": 200,
        "message": "latency is 0.127 seconds",
        "success": true
    }
}
```

Go ahead and pick another patter for global applications that boost the write performance. One of them is a geo-partitioned cluster that can store customer-specific data in the regions of their physical location and thus providing low latency for both reads and writes.

## Testing Geo-Partitioned Mode

1. Connect to the cluster with DataGrip or another SQL tool.

2. Apply the contents of the `/home/dmagda/sample_apps/YugaPlus/backend/src/main/resources/V2__create_geo_partitioned_user_library.sql`

3. Show that the write latency right now is in the single-digit millisecond range by removing/adding movies to the user libraries.
