# FuryDumper 🧙‍

Welcome to dumper gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/fury_dumper`. 

It help you to get dump from remote database in main service and other microservices, which has `fury_dumper` gem. 

*Read this in other languages: [Russian](README.ru.md).*

*For developers: [English](README_dev.md), [Russian](README_dev.ru.md).*

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'fury_dumper'
```

And then execute:

    bundle install

Or install it yourself as:

    gem install fury_dumper

## Usage

### Configuration

Create default configuration

    bundle exec rails generate fury_dumper:config

For correct work with other services change default `fury_dumper.yml` config. Structure description:

```yaml
# The size of the batch at the first iteration
#
# Optional; default 100
batch_size: 100

# The ratio of the number of records (fetching_records) uploaded from the database to the size of the batch
# Formula: fetching_records = ratio_records_batches * batch_size
# fetching_records acts as the limit value for sql queries
#
# Optional; default 10
ratio_records_batches: 10

# Track mode of the graph of relations - in width (:wide) or depth (:depth)
#
# Optional; default wide
mode: wide

# Relations that will be excluded from the dump,
# useful for speed optimization uploads and exceptions
# from unloading extra data:
# <class name>. <association name>
#
# Optional; default is empty array
exclude_relations: User.friends, Post.author

# By default, data is uploaded quickly (without sorting)
# fast mode allows you to dump records sorted by primary key (false) or not (true),
# useful for creating dumps for developers.
#
# Optional; default is true
fast: true

# List of microservice connections
#
# Optional
relative_services:
  # Microservice name
  #
  # Optional
  post_service:
    # Name of the remote database for this microservice (post_service)
    # with which data will dump
    #
    # Required
    database: 'post_service_development_dump'

    # Host for remote database
    #
    # Required
    host: 'localhost'

    # Port for remote database
    #
    # Required

    port: '5432'
    # Username for remote database
    #
    # Required
    user: 'user'

    # Password for remote database
    #
    # Required
    password: 'password'

    # A list of tables associated with this microservice (post_service)
    #
    # Required
    tables:
      # Table name with current service    
      #
      # Required
      users:

        # Table name in microservice (post_service)
        #
        # Required
        users:
          # Column name to the table of this service (users)
          #
          # Required
          self_field_name: 'id'

          # Model name in microservice (post_service)
          #
          # Required
          ms_model_name: 'User'

          # Name of the column to the microservice table (users)
          #
          # Required
          ms_field_name: 'root_user_id'
      root_posts:
        posts:
          self_field_name: 'id'
          ms_model_name: 'Post'
          ms_field_name: 'root_post_id'
  logs_service:
    database: 'logs_service_development_dump'
    host: 'localhost'
    port: '5432'
    user: 'user'
    password: 'password'
    tables:
      users:
        logs:
          self_field_name: "log :: json - >> 'id'"
          ms_model_name: 'Log'
          ms_field_name: 'id'
```

### Routing for microservices

Add this code to your `config/routes.rb` for add opportunity other services to dump your database:

```ruby
  mount FuryDumper::Engine => "fury_dumper" unless Rails.env.production?
```

### Main call

**⚠️ ⚠️ ⚠️ Attention! When copying data, in the event of a conflict with the available data, they are considered higher priority in the remote database (the current ones will overwrite)! ⚠️ ⚠️ ⚠️**

For start dumping from production or staging run this command: 

```ruby
FuryDumper.dump(password:     'password', 
                  host:         'localhost',
                  port:         '5632',
                  user:         'username',
                  model_name:   'User',
                  field_name:   'token',
                  field_values: ['99999999-8888-4444-1212-111111111111'],
                  database:     'staging',
                  debug_mode:   :short)
```

For connection to remote host, run ssh command. Example for main service stage:
```
ssh -NL <port>:<host>:<hostport> username@<host>
```

Description for arguments:

| Argument | Description |
| --- | --- |
| host | host for remote DB |
| port | port for remote DB |
| user | username for remote DB |
| password | password for remote DB |
| database | DB remote name |
| model_name | name of model for dump |
| field_name | field name for model |
| field_values | values of field_name |
| debug_mode | debug mode (full print all msgs, short - part of msgs, none -  nothing) |
| ask | ask user for confirm different schema of target & remote DB |


### Examples

In these examples it is not necessary to change the `fury_dumper.yml` config, take [default] (README.ru.md # configs).

User dump by admin_token:
```ruby
FuryDumper.dump(password:     'password', 
                  host:         'localhost',
                  port:         '5632',
                  user:         'username',
                  model_name:   'User',
                  field_name:   'admin_token',
                  field_values: [admin_token_value],
                  database:     'staging',
                  debug_mode:   :short)
```
Dump 1000 users (here you can tweak batch_size - by default batch_size = 100 so that the dumper worked more than 10 times):
```ruby
FuryDumper.dump(password:     'password', 
                  host:         'localhost',
                  port:         '5632',
                  user:         'username',
                  model_name:   'User',
                  field_values: (500..1500),
                  database:     'staging',
                  debug_mode:   :short)
```
Dump AdminUser:
```ruby
FuryDumper.dump(password:     'password', 
                  host:         'localhost',
                  port:         '5632',
                  user:         'username',
                  model_name:   'AdminUser',
                  field_values: 3368,
                  database:     'staging',
                  debug_mode:   :short)
```

Stage dump:

```bash
ssh -NL <port>:<host>:<hostport> username@<host>
```

```ruby
FuryDumper.dump(password:     'password', 
                  host:         'localhost',
                  port:         '5632',
                  user:         'username',
                  model_name:   'User',
                  field_values: 1,
                  database:     'staging',
                  debug_mode:   :short)
```

Dump from replica of production:

```bash
ssh -NL <port>:<host>:<hostport> username@<host>
```

```ruby
FuryDumper.dump(password:     'password', 
                  host:         'localhost',
                  port:         '5632',
                  user:         'username',
                  model_name:   'User',
                  field_values: 1,
                  database:     'production',
                  debug_mode:   :short)
```

### Statistics 📈

Dump statistics from the replica (standard configuration, see [this config](README.md#configuration))

| Number of base objects | Number of relative objects | Time |
| --- | --- | --- |
| 1 | ~ 150* | 2 min 14 sec |
| 10 | ~ 3 500* | 6 min 15 sec |
| 100 | ~ 10 000* | 11 min 8 sec |
| 1,000 | ~ 10 000* | 16 min 6 sec |

\ * Operations dump several times in different ways and can be duplicated among themselves, because of this the number presented in the table is approximately equal to the number of unique records in the database.

Note: The runtime may differ for different objects depending on the number relative objects.

# Dev documentation

Abbreviations for greater convenience
* PK - primary key
* FK - foreign key
* remote DB - remote DB from which data will be pulled
* target DB - the current database to which copying will be performed


## Track of the relation graph 

At the moment, 2 options have been implemented to keep track of the relation graph - in depth (depth-first) and in width (breadth-first).

### Depth first

How the algorithm works briefly:

1. Find a model
2. Find all model relationships
3. For each relation:
     1. Find all the data (PK / FK, values, etc.)
     2. Dump the found relation

That is a classic breadth-first algorithm

![Depth_first_example](Depth-first.png)

### Breadth first

How the algorithm works briefly:

1. Get the model for the dump (input data) and add it to the model queue
2. While there are models in queue
     1. The current model is considered the first in queue
     2. Copy this model from remote DB
     3. For each relation of this model:
         1. Find all the data (PK / FK, values, etc.)
         2. Put the linked model at the end of the queue

That is a classic breadth-first algorithm

![Breadth_first_example](Breadth-first.png)

By default, the dumper is wide. This decision was made due to the fact that the dumper considers short-range relations more priority. \
But you can explicitly make the dumper work in depth by specifying the string `mode: depth` in the configuration file` fury_dumper.yml`.

## Relationships for a specific model

Each model under consideration has many relations, we consider almost everything. Here is a list of relations being reviewed:
* has_one and has_many (considered together; has_one is not taken as LIMIT 1, thus converting to has_many)
* belongs_to
* has_and_belongs_to_many

But there are a few exceptions, for example, through relations are ignored.

And a little about scopes in relations - they are taken. But if there is a wider (covering relation) - without sсope, then only the covering relation will be dumped.

For example - the user has documents and a main documents:
* has_many :documents, class_name: 'User::Document'\
* has_one :main_document, -> { main }, class_name: 'User::Document'

Relation main_document will not be taken when dumping due to the fact that documents is a covering relation, since it is wider and without sсope.\
If there was no documents relation, main_document would dump with the condition.

Models also take with polymorphic relationships (`belongs_to: resource, polymorphic: true` and `has_many: devices, as:: owner`).

### has_and_belongs_to_many relation

The has_and_belongs_to_many associations have a proxy table that also needs to be dumped. This happens at the time of processing a model that has a given relationship.

### Features of as-relation
Relationships like as are handled a bit differently from the rest. Due to the fact that there can be many links to this table and they will not be duplicated, each carrying its own meaning and it is impossible to lose them. \
For example, a connection for the user `has_many: devices, as:: owner` may also be present in the lead. And in an ideal universe 🦄 , both need to be pulled out. \
In order to dump both models, it was decided to write down the relation path (only as) along which the model arrived. If one of the paths is a subpath for the other model, then they are the same and will not be dumped.

## Fast mode

Fast mode call sql queries without order by primary key. If you want to dump **last** records in model set `fast: false` in configuration.\
In fast mode sql queries look like this: 
```sql
SELECT * FROM table WHERE fk_id IN (...) LIMIT 1000;
```
In non-fast mode sql queries look like this: 
```sql
SELECT * FROM table WHERE fk_id IN (...) ORDER BY table.id LIMIT 1000
```
But non-fast mode makes queries slower due to the pg-planner building the query by primary key index and fk_id IN (...) filters when ordering. It works slower.

## Briefly about classes

* FuryDumper - initiates the dump process, performs batching on the first iteration
* FuryDumper :: Dumper - the main class that implements the dump process, the main algorithm for tracking relation here
* FuryDumper :: Dumper :: Model - model class
* FuryDumper :: Dumper :: ModelQueue - a queue of models for a dump in width
* FuryDumper :: Dumper :: DumpState - dump status class, information about those models that have already been dumped and some statistics  are stored here
* FuryDumper :: Dumper :: RelationItem - communication structure - keys and values ​​used to dump. For ordinary models, RelationItem is compared with each other only by key. The Additional option makes it possible to compare by key and value. Complex - explicitly says that there will only be a key, that is, the key contains a string of the type `date_from IS NULL`, which is a condition for communication.
* FuryDumper :: Api - a class for communicating with microservices
* FuryDumper :: Config - config class
* FuryDumper :: Encrypter - a class for encrypting passwords
