---
title: khmer Multiprocessing Project
subtitle: Progress Report
author: 
- name: Camille Welcher
  affiliation: Michigan State University
  email: welcherc@msu.edu
date: November 21, 2014
abstract: |
    The rise of high throughput sequencing has made sequence analysis a part of an increasing number of biological studies. However, as the capabilities of sequencers has increased, the computational methods necessary to handle such massive amounts of data have lagged behind. In particular, many algorithms for sequence analysis are extremely memory-intensive, and methods to reduce memory footprint are an area of active development. `k`-mer counting, the decomposition of sequences into a smaller overlapping subsequences of fixed length, has been shown to be very useful as an analysis paradigm, and Pell introduced a memory efficient way to store `k`-mer counts in fixed low-memory with a known false-positive rate using a count-min sketch [@pell_scaling_2012]. This method has been implemented in a widely used software package called `khmer`, which provides a simple Python interface to a highly optimized bloom-filter and count-min sketch written in C++. While the existing implentation has proven to be quite scalable and useful in a variety of applications [@brown_reference-free_2012], most of the software lacks parallelization. Here I will detail an effort to add a library of asynchronous, multithreaded extensions to `khmer`, with preliminary performance results under controlled conditions. Considering that `khmer`'s user base is estimated at over 10,000 active researchers, the impact of multiprocessor scalability to could be considerable.

...

## Introduction

To approach this project in a reasonable way, I have chosen to first focus on the improvement of a specific technique included called digital normalization, described in [@brown_reference-free_2012]. Briefly, digital normalization is a reference-free streaming algorithm to remove data while retaining information. It works by finding the median `k`-mer abundance of all `k`-mers ina sequencing read. If this median abundance is below a threshold chosen by the user, the read is kept and its `k`-mers are counted; if it is above the cutoff, we discard the read. This has the effecitve of "normalizing" the coverage of a dataset by using the median `k`-mer abundance as a proxy for coverage, without using a reference sequencing to determine what the "true" `k`-mer graph is. Thus, it is streaming and single-pass, which combined with its memory efficiency and linear-time complexity, makes it extremely desirable as a preprocessing step prior to the de novo assembly of reads. It has already been used in a number of groups' analyses, as well as being examined by Illumina as a method to reduce data size real time as reads come off the sequencing machine. Given the size of sequence datasets though, it is clearly beneficial to scale this performance with multiprocessor machines, and at first glance, pleasant scaling appears quite achievable.

There are currently several constraints, however:

1. Parallel writes to the hash table are currently difficult to support without locking, as the count-min sketch requires writing to `N` different tables, and `khmer` keeps track of unique `k`-mers as they are observed. There is also a functionality to track bins which have exceeded their maximum count in an STL map, which requires locking. The former constraint makes it difficult to assign each table its own thread; the latter makes it difficult to call the write function from different threads due to locking.

2. Distributed counting is extremely difficult. `k`-mer space is `k` dimensional, and data arrives in the stream essentially at random. Thus, designing an efficient way to subdivide `k`-mer space while reducing internode communiction is not immediately apparent. As such, this project will focus on single node, shared memory configurations; future work will explore efficient streaming graph partitioning to enable distributed implementations

3. Parallel IO for sequence data is non-trivial, and this is a bottleneck which we may not be able to reduce. As of now, this bottleneck has not been prohibitive, but I predict that it will be before the project is complete.

With this in mind, my project will attempt to scale digital normalization (and similar sequence processing methods) on shared-memory systems. In theory, I expect to achieve near-linear scaling, assuming to ability to develop effective multithreaded access to the underlying data structures. This new functionality will be exposed through the same simple Python interface currently used in `khmer`, and will thus be easy to integrate into existing scripts. Code is currently being actively developed on the `khmer` github repository on its own branch, with an active pull request to track changes and discussion found [here](https://github.com/ged-lab/khmer/pull/655). Code for writeups and performance testing can be found in a separate repository, also stored on [github](https://github.com/camillescott/khmer-metrics).

## Methods

The architecture of the project has soundly landed on asynchronous operations as a model. Operations are decomposed into asynchronously executed subtasks, which are combined to produce full functionality. The basic building block is the `khmer::Async` abstract base class, which:

* Manages thread state and error handling
* Launches threads through a defined `start(n_threads)` method
* Declares the existence of a `consume()` function which is expected to do the actual work
* Cleanly shuts down with a defined `stop()` method.

All threaded async functionality is exposed through classes inheriting from this base. `AsyncConsumer` and `AsyncProducer` are further abstract building blocks which define and input queue and push method or an output queue and pop method respectively, providing IO capabilities. An `AsyncConsumerProducer` inherits both of these classes, and an `AsyncSequenceProcessor` fills out the necessary functionality to:

* Parse reads asynchronously and place them on an input queue
* Declare a `consume` method to process these reads and place them on an output queue
* Write reads to the hash table asyncronously
* Expose a Python iterator over results in the output queue
* Manage all internal state

Finally, digital normalization is performed through the `AsyncDiginorm` class, which defines the `consume` method to perform the previously descibed operation, and places qualifying reads on both the output queue and the table writing queue. For now, we only maintain one thread for committing changes to the table, due to the above constraints. This has turned out to be a bottleneck, as this writer has to perform the hashing of `k`-mers to integers as well. Lower coverage cutoffs mean that less writes occur, and reduce this bottleneck with larger datasets, but this will eventually need to be addressed to realize full scaling potential.

One area of concern was the use of shared queue to manage resource access, as contention amongst threads could quickly mitigate any performance gains. This problem was resolved by using a lockfree queue provided by the `boost` library. Without getting into the details, a lockfree queue allows many threads to access a single queue in a non-blocking manner by providing a pool of temporary bins on a ring. Lockfree queues are only worthwhile in environments with many queue access operations, and with potentially hundreds of millions to billions of reads and tens of billions of `k`-mers, this is the perfect application.

Load balancing is also improved by operating at the read level instead of the `k`-mer level. Initial versions pushed hashed `k`-mers to the writer, but this caused too much queue contentention, and was resolved by pushing full reads and allowing the writer to decompose them indepently.

A more abstracted approach would move reads and sequences around in larger batches to further reduce queue contention. For example, as hashing is itself a completely independent operation, it might be beneficial for each `consume()` thread to do its own hashing of `k`-mers and deliver them to the writer thread in one package; this would save time in the writer, where the maximum queue size causes waiting on all `consume()` threads when the writer gets behind.

## Intitial Results

For basic threading capability, I have chosen to use C++11 standard library threads. This has the benefit of being completely cross-platform, while providing useful abstractions that libraries like pthreads fail to offer. I experimented with OpenMP, but its model was too simplistic for my needs, which drove the creation of the above described async architecture.

My initial results were taken using a high-performance on-demand Amazon EC2 instance. This runs Ubuntu 14.04, and has access to 32 physical Intel Xeon cores, 60 GiB of memory, 640GB of high-speed SSD, and a 10 gigabit networking interface. As of now, writing to the hashtable remains a signnificant bottleneck, which can be made apparent by looking at time spent waiting on queue per-thread. As queues do have a maximum size, and a thread will block until there is capacity available, and long wait times indicate saturated queues. Table 1 clearly shows that per-thread waiting stays almost constant as number of threads increases, which indicates that total wait time increases with thread count. On the other hand, both read wait and output wait decrease, with total wait time on these queues remaining constant. Nicely, this means that threaded IO is not yet a concern to contend with.

Threads     Reader-wait         Writer-wait     Output-wait
--------    ------------        ------------    -------------
1           14.3653             20.8402         9.49519
2           9.40681             13.9874	        4.29857
4           6.24932             20.1308	        2.54576
8           5.22319             21.2366	        2.25459
16          3.9894              21.9855	        1.76008
24          3.45136             15.2528	        1.53449
29          2.73944             23.9125	        1.24152

Table 1: per-thread time waiting on queues, seconds

With this in mind, the following performance results make sense. We only scale to approximately 2 consume threads, and then start to lose performance.

Threads  Time(s)
-------- --------
1        216.04 
2        130.47 
4        134.77
8        140.75
16       203.33
24       249.24
29       243.98

Table 2: Total time running digital normalization on a 40m read dataset (Sea lamprey)

## Future Work

The target of future work is clear: writing to the table must be optimized. The first way I will attempt to solve this problem will be through independently hashing and bundling, as decribed earlier; hashing takes considerably longer than writing to the table itself, so having this done independently is likely to be beneficial. If this is not enough, I will implement a version of hash tables `count()` function which ignores the STL map for counting overflow bins, allowing fast threadsafe writing. However, as this breaks the expected functionality of other existing scripts, it is my fallback option. Once this is complete, I will explore implementing other read processing methods which are currenly single-threaded. Finally, I intend to test on a variety of systems: Amazon also offers IO-optimized configurations, and HPC systems are a target.

A long-term goal is the exploration of NUMA optimizations. The random nature of the data means that NUMA architectures are slow for this problem, as cores must constantly run through each others' memory buses to retrieve non-local `k`-mer counts. Pinning cores to particular regions of the tables, and assigning threads to only handle certain `k`-mers, might allow the writer performance benefits.

## References
\setlength{\parindent}{-0.2in}
\setlength{\leftskip}{0.2in}
\setlength{\parskip}{8pt}
\vspace*{-0.2in}
\noindent
