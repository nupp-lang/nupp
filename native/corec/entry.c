/* entry.c: the C runtime's entry from the bridge, as the guest shim builds it
   for s0 (nupp.core.guestshim): lay out the scratch the bridge passes,
   prepare and open the services, start the bundle's entry module, run its
   handlers until no protected call resumes, complete it and close the
   services. The shim computes its layout when the bundle is built; this
   computes the same from the bundle's descriptor, so one runtime runs any
   bundle of the version it reads. */
#include "context.h"
#include "frames.h"
#include "guestcatalog.h"
#include "guestentry.h"
#include "guestscope.h"
#include "guestuncaught.h"
#include "instances.h"
#include "nuppedges.h"

extern const nupp_handler nupp_dispatch[256];

uint64_t *nupp_os_imports;

/* The packet the bridge passes. */
enum {
  PACKET_VERSION,
  PACKET_CODE,
  PACKET_CODE_BYTES,
  PACKET_DATA,
  PACKET_DATA_BYTES,
  PACKET_SCRATCH,
  PACKET_SCRATCH_BYTES,
  PACKET_OS_IMPORTS,
  PACKET_RESERVED,
  PACKET_LIMITS,
  PACKET_LIMIT_COUNT,
  PACKET_MODULES
};

/* The scratch the shim lays out, and the services' share of it. */
#define SCRATCH_BYTES 1048576
#define SERVICES_BYTES 12288

/* The dispatch table: one handler address per opcode. */
#define DISPATCH_ENTRIES 256
#define DISPATCH_ENTRY_BYTES ((uint64_t)sizeof(void *))
#define DISPATCH_BYTES (DISPATCH_ENTRIES * DISPATCH_ENTRY_BYTES)

/* A mapped frame pool's first chunk, at most (guestshim FIRST_POOL). */
#define FIRST_POOL 262144

/* The descriptor version from which only the entry module runs at first and
   storage and the frame pool are mapped as the services open. */
#define LAZY_VERSION 8

static uint64_t align16 (uint64_t value) {
  return (value + 15) & ~(uint64_t)15;
}

static void *at (uint64_t scratch, uint64_t offset) {
  return (void *)(uintptr_t)(scratch + offset);
}

/* The largest frame any of the bundle's functions takes. */
static uint64_t maximumFrame (const guestcatalog_Descriptor *descriptor) {
  const uint8_t *data = (const uint8_t *)descriptor;
  const guestcatalog_Function *records =
      (const guestcatalog_Function *)(data + descriptor->records);
  uint64_t frame = align16(sizeof(frames_Frame));
  uint64_t largest = 0;

  for (uint64_t index = 0; index < descriptor->ownerCount; ++index) {
    uint64_t bytes = align16(frame + records[index].valueCount * 8);

    if (bytes > largest) {
      largest = bytes;
    }
  }

  return largest;
}

/* Runs the handlers of `frame` from `pc` until one returns. */
static void run (void *ctx, frames_Frame *frame, uint64_t pc) {
  void *code = (void *)(uintptr_t)pc;
  nupp_dispatch[*(const uint8_t *)code](code, (void *)(uintptr_t)frame->values,
                                        (void *)(uintptr_t)frame->integers,
                                        (void *)(uintptr_t)frame->floats, ctx,
                                        frame);
}

uint64_t nupp_c_entry (const uint64_t *packet, uint64_t *output) {
  const uint64_t *limits = (const uint64_t *)(uintptr_t)packet[PACKET_LIMITS];
  uint64_t limitCount = packet[PACKET_LIMIT_COUNT];

  if (packet[PACKET_VERSION] != 1 ||
      packet[PACKET_SCRATCH_BYTES] < SCRATCH_BYTES ||
      packet[PACKET_MODULES] < 1 ||
      packet[PACKET_DATA_BYTES] < sizeof(guestcatalog_Descriptor) ||
      limitCount > 3) {
    return 1;
  }

  const guestcatalog_Descriptor *descriptor =
      (const guestcatalog_Descriptor *)(uintptr_t)packet[PACKET_DATA];

  if (descriptor->version < LAZY_VERSION || descriptor->moduleCount < 1) {
    return 1;
  }

  /* The shim's layout (guestshim.build), for one lazily loaded module. */
  uint64_t worldAt = align16(CONTEXT_SIZE);
  uint64_t bindingAt = align16(worldAt + sizeof(instances_World));
  uint64_t dispatchAt = align16(bindingAt + sizeof(guestentry_Binding));
  uint64_t servicesAt = align16(dispatchAt + DISPATCH_BYTES);
  uint64_t helperAt = align16(servicesAt + SERVICES_BYTES);
  uint64_t largest = maximumFrame(descriptor);
  uint64_t poolBytes = descriptor->frameDepth * largest;
  uint64_t firstPool = largest > FIRST_POOL ? largest : FIRST_POOL;

  if (poolBytes < firstPool) {
    firstPool = poolBytes;
  }

  uint64_t capacity =
      descriptor->instanceBound == 0 ? 1 : descriptor->instanceBound;
  uint64_t storageBytes =
      guestentry_storageBytes(descriptor->ownerCount, capacity);

  nupp_os_imports = (uint64_t *)(uintptr_t)packet[PACKET_OS_IMPORTS];
  uint64_t scratch = packet[PACKET_SCRATCH];
  void *services = (void *)(uintptr_t)guestscope_prepareOwned(
      at(scratch, servicesAt), SERVICES_BYTES);

  if (services == NULL) {
    return 1;
  }

  uint64_t result = 1;
  servicescope_ServiceScope *scope = (servicescope_ServiceScope *)services;
  guestscope_Services *held = (guestscope_Services *)services;
  uint64_t stress = limitCount >= 3 ? limits[2] : 0;

  if (guestscope_open(services, 0, storageBytes, 1, firstPool,
                      scratch + worldAt, stress, scope) != 1) {
    goto close;
  }

  void *ctx = at(scratch, 0);

  for (int64_t offset = 0; offset < CONTEXT_SIZE; offset += 8) {
    if (native_load64(ctx, offset) != 0) {
      goto close;
    }
  }

  void *table = at(scratch, dispatchAt);
  native_storePointer(ctx, CONTEXT_DISPATCH_TABLE, table);
  native_store64(ctx, CONTEXT_CANCELLED, limitCount >= 2 ? limits[1] : 0);
  native_store64(ctx, CONTEXT_STATUS, 0);
  native_store64(ctx, CONTEXT_ERROR_PC, 0);
  native_store64(ctx, CONTEXT_REMAINING,
                 limitCount != 0 ? limits[0] : CONTEXT_UNLIMITED);

  guestentry_Binding *binding = at(scratch, bindingAt);
  binding->data = packet[PACKET_DATA];
  binding->dataBytes = packet[PACKET_DATA_BYTES];
  binding->code = packet[PACKET_CODE];
  binding->codeBytes = packet[PACKET_CODE_BYTES];
  binding->context = (uint64_t)(uintptr_t)ctx;
  binding->contextBytes = CONTEXT_SIZE;
  binding->world = scratch + worldAt;
  binding->worldBytes = sizeof(instances_World);
  binding->storage = held->storage;
  binding->storageBytes = storageBytes;
  binding->pool = held->pool;
  binding->poolBytes = held->poolbytes;
  binding->helper = scratch + helperAt;
  binding->helperBytes = SCRATCH_BYTES - helperAt;

  frames_Frame *root = (frames_Frame *)(uintptr_t)guestentry_start(
      binding, descriptor->moduleCount - 1);

  if (root == NULL) {
    goto close;
  }

  native_storePointer(ctx, CONTEXT_SERVICE_SCOPE, services);
  uint64_t serial = native_load64(ctx, CONTEXT_ROOT_SERIAL);

  for (uint64_t index = 0; index < DISPATCH_ENTRIES; ++index) {
    native_storePointer(table, (int64_t)(index * DISPATCH_ENTRY_BYTES),
                        (void *)nupp_dispatch[index]);
  }

  native_store64(ctx, CONTEXT_CODE_START, root->code);
  run(ctx, root, root->code);

  for (;;) {
    uint64_t resume = guestuncaught_recover(ctx, scope);

    if (resume == 0) {
      break;
    }

    frames_State *state = native_loadPointer(ctx, CONTEXT_STATE);
    run(ctx, (frames_Frame *)(uintptr_t)state->active, resume);
  }

  uint64_t status = native_load64(ctx, CONTEXT_STATUS);
  uint64_t completed = guestentry_complete(ctx, root, serial);

  if (status != 0) {
    result = status;
  }
  else if (completed == 1) {
    frames_RootControl *control = native_loadPointer(ctx, CONTEXT_ROOT_CONTROL);
    output[0] = control->value;
    result = 0;
  }

close:
  guestscope_close(services, scope);
  uint64_t problem = guestscope_finish(services);

  if (problem != 0 && result <= 1) {
    result = 256 + problem;
  }

  return result;
}
