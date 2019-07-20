all: sdl2test-system sdl2test-zino sdl2test-retropie

clean:
	rm sdl2test-system sdl2test-zino sdl2test-retropie

sdl2test-system: sdl2test.c
	gcc $(shell sdl2-config --cflags --libs) -v -o sdl2test-system sdl2test.c

sdl2test-zino: sdl2test.c
	gcc $(shell /opt/zino/bin/sdl2-config --cflags --libs) -v -o sdl2test-zino sdl2test.c

sdl2test-retropie: sdl2test.c
	gcc $(shell /opt/retropie/bin/sdl2-config --cflags --libs) -v -o sdl2test-retropie sdl2test.c
