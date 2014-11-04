#!/usr/bin/env python

import khmer
import sys

def write_read(record, outfp):
    if hasattr(record, 'accuracy'):
        outfp.write(
            '@{name}\n{seq}\n'
            '+\n{acc}\n'.format(name=record.name,
                                seq=record.sequence,
                                acc=record.accuracy))
    else:
        outfp.write(
            '>{name}\n{seq}\n'.format(name=record.name,
                                      seq=record.sequence))

def main():
    fn = sys.argv[1]
    ht = khmer.new_counting_hash(20, 1e8, 4)
    async = khmer.AsyncDiginorm(ht)

    print "Created ht, AsyncDiginorm object. Starting processor threads..."
    async.start(fn, 5, 4)

    print "Processors started, start popping results..."

    n_kept = 0
    with open(fn + '.async.keep', 'wb') as fp:
        for read in async.processed():
            n_kept += 1
            #if n_kept % 10000 == 0:
            #    print "test_async:", read.name, read.sequence
            write_read(read, fp)

    async.stop()

if __name__ == '__main__':
    main()
