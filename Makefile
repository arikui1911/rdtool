all: build

clean:
	rm -fr _site

src_clean:
	( cd rd && make distclean )

distclean: clean src_clean

build: 
	@[ ! -f `which jekyll` ] || jekyll --no-auto

server: 
	@[ ! -f `which jekyll` ] || jekyll --server --url=""

