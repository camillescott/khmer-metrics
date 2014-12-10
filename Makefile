all: abstract.pdf about.pdf

ECOLI=test-ecoli-1m.fa
PMZ=petMar.AI.4m.fq.gz

#abstract.pdf: abstract.md
#	pandoc -r markdown+yaml_metadata_block -s -S --latex-engine=pdflatex --template=latex.tpl abstract.md -o abstract.pdf

about.pdf: about.md
	pandoc -r markdown+yaml_metadata_block -s -S --latex-engine=pdflatex --template=latex.tpl $< -o $@

progress_report.pdf: progress_report.md
	pandoc -r markdown+yaml_metadata_block+table_captions+simple_tables -s -S --latex-engine=pdflatex --bibliograph=omics.bib --template=latex.tpl $< -o $@	

diginorm_async.prof:
	python -m yep -o $@ -- `which normalize-by-median.py-async` -C 5 -k 20 -x 1e9 $(PMZ)
	

diginorm_async_callgraph.svg: diginorm_async.prof
	google-pprof --svg /usr/bin/python-dbg $< > $@

diginorm_sync.prof:
	python -m yep -o $@ -- `which normalize-by-median.py` -C 5 -k 20 -x 1e9 $(PMZ)
	

diginorm_sync_callgraph.svg: diginorm_sync.prof
	google-pprof --svg /usr/bin/python-dbg $< > $@
