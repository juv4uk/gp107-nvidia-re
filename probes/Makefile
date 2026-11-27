CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11

TARGET := 01_min_cuinit

all: $(TARGET)

$(TARGET): $(TARGET).c
	$(CC) $(CFLAGS) -o $@ $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all run clean
