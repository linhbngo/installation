#!/usr/bin/env bash

# First steps:
#     - create a new ipython notebook config for using spark in the notebook:
#       - https://ipython.org/ipython-doc/3/config/intro.html
#         ipython profile create spark_on_yarn
#     - generate a hashed password:
#         module add anaconda/2.5.0
#         python
#         from IPython.lib import passwd
#         passwd()
#     - Then add your password to the config file like so:
#         # Password to use for web authentication
#         c = get_config()
#         c.NotebookApp.password = u'sha1:<HASHED_PASSWORD>'

NB_CONFIG=~/.ipython/profile_spark_on_yarn/ipython_config.py
export HDP_VERSION=2.4.2.0-258
export PYSPARK_DRIVER_PYTHON=/software/anaconda/2.5.0/bin/ipython
export PYSPARK_DRIVER_PYTHON_OPTS="notebook --notebook-dir=$HOME --config=$NB_CONFIG --ip=localhost --no-mathjax"

# How best to tune parallelism and workflow?
#     http://blog.cloudera.com/blog/2015/03/how-to-tune-your-apache-spark-jobs-part-1/
#     http://blog.cloudera.com/blog/2015/03/how-to-tune-your-apache-spark-jobs-part-2/

# Some example math:
#    example numbers: 6 nodes, 16 cores, 64 gb memory
#    example sets aside: 1 core and 1 GB for OS, we leave more
# For yarn.nodemanager.resource.cpu-vcores:
#     15, node001-node006
# For yarn.nodemanager.resource.memory-mb:
#     (63 * 1024), node001-node006
#
# Don't do: --num-executors 6 --executor-cores 15 --executor-memory 63G
#
# Better: --num-executors 17 --executor-cores 5 --executor-memory 19G. Why?
#
# I don't understand where the --executor-cores 5 comes from...
#      - apparently, "15 cores per executor can lead to bad HDFS I/O throughput."
#      - TODO: test different values for this on different workloads and assess performance
#
#
# Do math:
#     - Assumptions: 3 executors per node
#     - Assumptions: use --executor-cores 5 as an upper bound for now, calculated using cores/executors
#                  e.g. 15 / 3 = 5
#     --executor-memory was derived as (63/3 executors per node) = 21.
#         e.g. 21 * 0.07 = 1.47.  21 – 1.47 ~ 19 <--- use this number
#     - See the tuning parallelism guide for where .07 comes from
#         - (hint: overhead for spark on yarn executor memory overhead)

# Cypress:
# For yarn.nodemanager.resource.cpu-vcores:
#     22, dsci001-dsci016
#     44, dsci017-dsci040
# For yarn.nodemanager.resource.memory-mb:
#     191488, dsci001-dsci016
#     225280, dsci017-dsci040

# Now what?:
# compute for the first range: dsci001-dsci016
#   3 executors per node, 3 * 16 = 48 executors
#   22 / 3 = 7 cores per executors
#   executor-memory: 191488 / 3 ~ 63829. 63829 * .07 = 4468.
#                    63829 - 4468 = 59361m. ~58g. use 57g though if using g <--- floor and round down
#
# compute for the first range: dsci017-dsci040
#   3 executors per node (4 or 6 might be better?) = 3 * 24 = 72 executors
#   4 / 3 = 14 cores per executor
#   executor-memory: 225280 / 3 ~ 75093. 75093 * .07 = 5256.
#                    75093 - 5256 = 69837m. ~68g. <--- floor and round down
#
#   now what?
#   a stab in the dar: 3 executors per node
#                      14 cores per executor (nodes 001-016 will have left over cores but it's not too bad)
#                      68g per executors wastes a lot of memory on dsci001-dsci016 due to only one executor being able to be allocated
#                          wasted memory = (191488m - (63829*2)) * 16 = ~ 1t
#                          wasted cores = (22 - 14) * 16 = 128 vcores
#   other way: 3 executors per node on 001-016 and 6 executors per on 017-040 = 3*16+6*24 = 192 executors
#              7 cores per executor
#                  waste: wasted cores = 1*16 + 2*24 = 64
#              memory: since i doubled #exec on 017-040, need to recalculate memory, (75093/2 * .93) = 34918
#                  waste: 16 * (191488 - 3*34918) + 24 * (225280 - 6 * 34918) = 1724 gb
#   what if we also double executors on 001-016?
#       same cores per executor (7) and 6 executors on all nodes = 240
#           waste: 16 * (22 % 7) + 24 * (44 % 7) = 64 cores
#       memory: 63829/2 * .93 = 29680
#           waste: 16 * (191488 - 6*29680) + 24 * (225280 - 6*29680) = 1315 gb
#          
#
#
pyspark \
  --master yarn \
  --num-executors 40 \
  --executor-cores 4 \
  --executor-memory 178082m \
  --driver-memory 16g # NOTE: If launched from dsciu001, the driver will run on dsciu001

