---
title: khmer Multiprocessing Project
subtitle: Progress Report
author: 
- name: Camille Welcher
  affiliation: Michigan State University
  email: welcherc@msu.edu
date: November 21, 2014
abstract: |
    The rise of high throughput sequencing has made sequence analysis a part of an increasing number of biological studies. However, as the capabilities of sequencers has increased, the computational methods necessary to handle such massive amounts of data have lagged behind. In particular, many algorithms for sequence analysis are extremely memory-intensive, and methods to reduce memory footprint are an area of active development. `k`-mer counting, the decomposition of sequences into a smaller overlapping subsequences of fixed length, has been shown to be very useful as an analysis paradigm, and Pell introduced a memory efficient way to store `k`-mer counts in fixed low-memory with a known false-positive rate using a count-min sketch. This method has been implemented in a widely used software package called `khmer`, which provides a simply Python interface to a highly optimized bloom-filter and countmin sketch written in C++. While the existing implentation has proven to be quite scalable and useful in a variety of applications (cite Diginorm, Chikli, howe), most of the software lacks parallelization. Here I will detail an effort to add a library of asynchronous, multithreaded extensions to `khmer`, with preliminary performance results under controlled conditions. Considering that `khmer`'s user base is estimated at over 10,000 active researchers, the impact of multiprocessor scalability to could be considerable.

...

## Introduction

To approach this project in a reasonable way, I have chosen to first focus on the improvement of a specific technique included called digital normalization, described in Brown (Cite). Briefly, digital normalization is a reference-free streaming algorithm to remove data while retaining information. It works by finding the median `k`-mer abundance of all `k`-mers ina sequencing read. If this median abundance is below a threshold chosen by the user, the read is kept and its `k`-mers are counted; if it is above the cutoff, we discard the read. This has the effecitve of "normalizing" the coverage of a dataset by using the median `k`-mer abundance as a proxy for coverage, without using a reference sequencing to determine what the "true" `k`-mer graph is. Thus, it is streaming and single-pass, which combined with its memory efficiency and linear-time complexity, makes it extremely desirable as a preprocessing step prior to the de novo assembly of reads. It has already been used in a number of groups' analyses (Lowe, Howe, Schwarz), as well as being examined by Illumina as a method to reduce data size real time as reads come off the sequencing machine. Given the size of sequence datasets though, it is clearly beneficial to scale this performance with multiprocessor machines, and at first glance, pleasant scaling appears quite achievable.

There are currently several constraints, however:

1. Parallel writes to the hash table are currently difficult to support without locking, as the count-min sketch requires writing to `N` different tables, and `khmer` keeps track of unique `k`-mers as they are observed. There is also a functionality to track bins which have exceeded their maximum count in an STL map, which requires locking. The former constraint makes it difficult to assign each table its own thread; the latter makes it difficult to call the write function from different threads due to locking.

2. Distributed counting is extremely difficult. `k`-mer space is `k` dimensional, and data arrives in the stream essentially at random. Thus, designing an efficient way to subdivide `k`-mer space while reducing internode communiction is not immediately apparent. As such, this project will focus on single node, shared memory configurations; future work will explore efficient streaming graph partitioning to enable distributed implementations

3. Parallel IO for sequence data is non-trivial, and this is a bottleneck which we may not be able to reduce. As of now, this bottleneck has not been prohibitive, but I predict that it will be before the project is complete.

With this in mind, my project will attempt to scale digital normalization (and similar sequence processing methods) on shared-memory systems. In theory, I expect to achieve near-linear scaling, assuming to ability to develop effective multithreaded access to the underlying data structures. This new functionality will be exposed through the same simple Python interface currently used in `khmer`, and will thus be easy to integrate into existing scripts. Code is currently being actively developed on the `khmer` github repository on its own branch, with an active pull request to track changes and discussion found [here](https://github.com/ged-lab/khmer/pull/655). Code for writeups and performance testing can be found in a separate repository, also stored on [github](https://github.com/camillescott/khmer-metrics).

## Shared-memory Model

Most of the code for the hashtables and data parsing has already been made threadsafe in the C++ API[^4]. However, there is a design challenge in how best to bridge the gap between the Python API which is limited by the Global Interpreter Lock (GIL) and that C++ API. If we spawn threads in the Python layer and rely on the C++ implementations to unlock the GIL (as is currently done), we gain no real performance, because the Pythin threads still block each other. There are several possible approaches to this problem.

A first option 


[^1]: https://github.com/ged-lab/khmer
[^2]: http://ged.msu.edu/
[^3]: https://github.com/camillescott/fs2014-cse891/tree/master/final
[^4]: http://khmer.readthedocs.org/en/v1.1/design.html
