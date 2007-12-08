# Makefile

ifneq (,$(findstring 2.6,$(KERNELRELEASE)))
EXTRA_CFLAGS += -D KERNEL26
obj-m := kaodv.o
else
SRC =	main.c list.c debug.c timer_queue.c aodv_socket.c aodv_hello.c \
	aodv_neighbor.c aodv_timeout.c routing_table.c seek_list.c \
	k_route.c aodv_rreq.c aodv_rrep.c aodv_rerr.c packet_input.c \
	packet_queue.c libipq.c icmp.c

SRC_NS = 	debug.c list.c timer_queue.c aodv_socket.c aodv_hello.c \
		aodv_neighbor.c aodv_timeout.c routing_table.c seek_list.c \
		aodv_rreq.c aodv_rrep.c aodv_rerr.c packet_input.c \
		packet_queue.c

SRC_NS_CPP =	aodv-uu.cc

OBJS =	$(SRC:%.c=%.o)
OBJS_ARM = $(SRC:%.c=%-arm.o)
OBJS_MIPS = $(SRC:%.c=%-mips.o)
OBJS_NS = $(SRC_NS:%.c=%-ns.o)
OBJS_NS_CPP = $(SRC_NS_CPP:%.cc=%-ns.o)

KERNEL=$(shell uname -r)
# Change to compile against different kernel (can be overridden):
KERNEL_DIR=/lib/modules/$(KERNEL)/build
KERNEL_INC=$(KERNEL_DIR)/include

# Some shell scripting to find out Linux kernel version
VERSION=$(shell if [ ! -d $(KERNEL_DIR) ]; then echo "No linux source found!!! Check your setup..."; exit; fi; grep ^VERSION $(KERNEL_DIR)/Makefile | cut -d' ' -f 3)
PATCHLEVEL=$(shell grep ^PATCHLEVEL $(KERNEL_DIR)/Makefile | cut -d' ' -f 3)
SUBLEVEL=$(shell grep ^SUBLEVEL $(KERNEL_DIR)/Makefile | cut -d' ' -f 3)

# Compiler and options:
CC=gcc
# You might want to use gcc32 for the kernel module on Fedora core 1
KCC=gcc
ARM_CC=arm-linux-gcc
MIPS_CC=mipsel-uclibc-gcc
CPP=g++
OPTS=-Wall -O3
CPP_OPTS=-Wall

# Comment out to disable debug operation...
DEBUG=-g -DDEBUG
# Add extra functionality. Uncomment or use "make DEFS=-D<feature>" on 
# the command line.
DEFS=-DCONFIG_GATEWAY#-DLLFEEDBACK
CFLAGS=$(OPTS) $(DEBUG) $(DEFS)
LD=

ifneq (,$(findstring CONFIG_GATEWAY,$(DEFS)))
SRC:=$(SRC) min_ipenc.c locality.c
endif
ifneq (,$(findstring LLFEEDBACK,$(DEFS)))
SRC:=$(SRC) llf.c
LD:=-liw
endif

# ARM specific configuration goes here:
#=====================================
ARM_INC=

# NS specific configuration goes here:
#=====================================
NS_DEFS= # DON'T CHANGE (overridden by NS Makefile)

# Set extra DEFINES here. Link layer feedback is now a runtime option.
EXTRA_NS_DEFS=-DCONFIG_GATEWAY

ifneq (,$(findstring CONFIG_GATEWAY,$(EXTRA_NS_DEFS)))
SRC_NS:=$(SRC_NS) locality.c
endif

# Note: OPTS is overridden by NS Makefile
NS_CFLAGS=$(OPTS) $(CPP_OPTS) $(DEBUG) $(NS_DEFS) $(EXTRA_NS_DEFS)

NS_INC= # DON'T CHANGE (overridden by NS Makefile)

# Archiver and options
AR=ar
AR_FLAGS=rc

# These are the options for the kernel module with kernel 2.4.x:
#==============================================
KINC=-nostdinc $(shell $(CC) -print-search-dirs | sed -ne 's/install: \(.*\)/-I \1include/gp') -I$(KERNEL_INC)
KDEFS=-D__KERNEL__ -DMODULE
KCFLAGS=-Wall -O2 $(KDEFS) $(KINC)
KCFLAGS_ARM=-Wall -O2 -D__KERNEL__ -DMODULE -nostdinc $(shell $(ARM_CC) -print-search-dirs | sed -ne 's/install: \(.*\)/-I \1include/gp') -I$(KERNEL_INC)
KCFLAGS_MIPS=-Wall -mips2 -O2 -fno-pic -mno-abicalls -mlong-calls -G0 -msoft-float -D__KERNEL__ -DMODULE -nostdinc $(shell $(MIPS_CC) -print-search-dirs | sed -ne 's/install: \(.*\)/-I \1include/gp') -I$(KERNEL_INC)

.PHONY: default clean install uninstall depend tags aodvd-arm docs

# Check for kernel version
ifeq ($(PATCHLEVEL),6)
default: aodvd kaodv.ko
else 
# Assume kernel 2.4
default: aodvd kaodv.o
endif

arm: aodvd-arm kaodv-arm.o

ns: endian.h aodv-uu.o

endian.h:
	$(CC) $(CFLAGS) -o endian endian.c
	./endian > endian.h

$(OBJS): %.o: %.c Makefile
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJS_ARM): %-arm.o: %.c Makefile
	$(ARM_CC) $(CFLAGS) -DARM $(ARM_INC) -c -o $@ $<

$(OBJS_MIPS): %-mips.o: %.c Makefile
	$(MIPS_CC) $(CFLAGS) -DMIPS $(MIPS_INC) -c -o $@ $<

$(OBJS_NS): %-ns.o: %.c Makefile
	$(CPP) $(NS_CFLAGS) $(NS_INC) -c -o $@ $<

$(OBJS_NS_CPP): %-ns.o: %.cc Makefile
	$(CPP) $(NS_CFLAGS) $(NS_INC) -c -o $@ $<

aodvd: $(OBJS) Makefile
	$(CC) $(CFLAGS) $(LD) -o $@ $(OBJS)

aodvd-arm: $(OBJS_ARM) Makefile
	$(ARM_CC) $(CFLAGS) -DARM -o $(@:%-arm=%) $(OBJS_ARM)

aodvd-mips: $(OBJS_MIPS) Makefile
	$(MIPS_CC) $(CFLAGS) -DMIPS -o $(@:%-mips=%) $(OBJS_MIPS)

aodv-uu.o: $(OBJS_NS_CPP) $(OBJS_NS)
	$(AR) $(AR_FLAGS) libaodv-uu.a $(OBJS_NS_CPP) $(OBJS_NS) > /dev/null

# Kernel module:
kaodv.o: kaodv.c
	$(KCC) $(KCFLAGS) -c -o $@ $<

kaodv.ko: kaodv.c
	$(MAKE) -C $(KERNEL_DIR) SUBDIRS=$(PWD) modules

kaodv-arm.o: kaodv.c
	$(ARM_CC) $(KCFLAGS_ARM) -c -o $(@:%-arm.o=%.o) $<

kaodv-mips.o: kaodv.c
	$(MIPS_CC) $(KCFLAGS_MIPS) -c -o $(@:%-mips.o=%.o) $<
tags:
	etags *.c *.h
indent:
	indent -kr -l 80 *.c \
	$(filter-out $(SRC_NS_CPP:%.cc=%.h),$(wildcard *.h))
depend:
	@echo "Updating Makefile dependencies..."
	@makedepend -Y./ -- $(DEFS) -- $(SRC) &>/dev/null
	@makedepend -a -Y./ -- $(KDEFS) kaodv.c &>/dev/null

install: default
	install -s -m 755 aodvd /usr/sbin/aodvd
	@if [ ! -d /lib/modules/$(KERNEL)/aodv ]; then \
		mkdir /lib/modules/$(KERNEL)/aodv; \
	fi

	@echo "Installing kernel module in /lib/modules/$(KERNEL)/aodv/";
	@if [ -f ./kaodv.ko ]; then \
		install -m 644 kaodv.ko /lib/modules/$(KERNEL)/aodv/kaodv.ko; \
	else \
		install -m 644 kaodv.o /lib/modules/$(KERNEL)/aodv/kaodv.o; \
	fi
	/sbin/depmod -a
uninstall:
	rm -f /usr/sbin/aodvd
	rm -rf /lib/modules/$(KERNEL)/aodv

docs:
	cd docs && $(MAKE) all
clean: 
	rm -f aodvd *~ *.o core *.log libaodv-uu.a endian endian.h *.ko *.mod.[co] .*.cmd *.ver *.mod .*.d
#cd docs && $(MAKE) clean

endif

# DO NOT DELETE

main.o: defs.h timer_queue.h list.h debug.h params.h aodv_socket.h
main.o: aodv_rerr.h routing_table.h aodv_timeout.h k_route.h aodv_hello.h
main.o: aodv_rrep.h packet_input.h packet_queue.h
list.o: list.h
debug.o: aodv_rreq.h defs.h timer_queue.h list.h seek_list.h routing_table.h
debug.o: aodv_rrep.h aodv_rerr.h debug.h params.h
timer_queue.o: timer_queue.h defs.h list.h debug.h
aodv_socket.o: aodv_socket.h defs.h timer_queue.h list.h aodv_rerr.h
aodv_socket.o: routing_table.h params.h aodv_rreq.h seek_list.h aodv_rrep.h
aodv_socket.o: aodv_hello.h aodv_neighbor.h debug.h
aodv_hello.o: aodv_hello.h defs.h timer_queue.h list.h aodv_rrep.h
aodv_hello.o: routing_table.h aodv_timeout.h aodv_rreq.h seek_list.h params.h
aodv_hello.o: aodv_socket.h aodv_rerr.h debug.h
aodv_neighbor.o: aodv_neighbor.h defs.h timer_queue.h list.h routing_table.h
aodv_neighbor.o: aodv_rerr.h aodv_hello.h aodv_rrep.h aodv_socket.h params.h
aodv_neighbor.o: debug.h
aodv_timeout.o: defs.h timer_queue.h list.h aodv_timeout.h aodv_socket.h
aodv_timeout.o: aodv_rerr.h routing_table.h params.h aodv_neighbor.h
aodv_timeout.o: aodv_rreq.h seek_list.h aodv_hello.h aodv_rrep.h debug.h
aodv_timeout.o: packet_queue.h k_route.h icmp.h
routing_table.o: routing_table.h defs.h timer_queue.h list.h aodv_timeout.h
routing_table.o: packet_queue.h aodv_rerr.h aodv_hello.h aodv_rrep.h
routing_table.o: aodv_socket.h params.h k_route.h debug.h seek_list.h
seek_list.o: seek_list.h defs.h timer_queue.h list.h aodv_timeout.h params.h
seek_list.o: debug.h
k_route.o: defs.h timer_queue.h list.h debug.h k_route.h
aodv_rreq.o: aodv_rreq.h defs.h timer_queue.h list.h seek_list.h
aodv_rreq.o: routing_table.h aodv_rrep.h aodv_timeout.h k_route.h
aodv_rreq.o: aodv_socket.h aodv_rerr.h params.h debug.h locality.h
aodv_rrep.o: aodv_rrep.h defs.h timer_queue.h list.h routing_table.h
aodv_rrep.o: aodv_neighbor.h aodv_hello.h aodv_timeout.h aodv_socket.h
aodv_rrep.o: aodv_rerr.h params.h debug.h
aodv_rerr.o: aodv_rerr.h defs.h timer_queue.h list.h routing_table.h
aodv_rerr.o: aodv_socket.h params.h aodv_timeout.h debug.h
packet_input.o: defs.h timer_queue.h list.h debug.h routing_table.h
packet_input.o: aodv_hello.h aodv_rrep.h aodv_rreq.h seek_list.h aodv_rerr.h
packet_input.o: libipq.h params.h aodv_timeout.h aodv_socket.h packet_queue.h
packet_input.o: packet_input.h min_ipenc.h
packet_queue.o: packet_queue.h defs.h timer_queue.h list.h debug.h
packet_queue.o: routing_table.h libipq.h params.h aodv_timeout.h min_ipenc.h
libipq.o: libipq.h
icmp.o: defs.h timer_queue.h list.h debug.h
min_ipenc.o: defs.h timer_queue.h list.h debug.h min_ipenc.h
locality.o: locality.h defs.h timer_queue.h list.h debug.h
