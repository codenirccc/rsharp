extern "vulkan" fn vkCreateInstance(info: ptr<u8>, allocator: ptr<u8>, instance: ptr<ptr<u8>>) -> i32;
extern "vulkan" fn vkEnumeratePhysicalDevices(instance: ptr<u8>, count: ptr<u32>, devices: ptr<ptr<u8>>) -> i32;
extern "vulkan" fn vkGetPhysicalDeviceProperties(device: ptr<u8>, props: ptr<u8>) -> void;
extern "vulkan" fn vkGetPhysicalDeviceFeatures(device: ptr<u8>, features: ptr<u8>) -> void;
extern "vulkan" fn vkGetPhysicalDeviceQueueFamilyProperties(device: ptr<u8>, count: ptr<u32>, props: ptr<u8>) -> void;
extern "vulkan" fn vkCreateDevice(physicalDevice: ptr<u8>, info: ptr<u8>, allocator: ptr<u8>, device: ptr<ptr<u8>>) -> i32;
extern "vulkan" fn vkGetDeviceQueue(device: ptr<u8>, familyIndex: u32, queueIndex: u32, queue: ptr<ptr<u8>>);
extern "vulkan" fn vkDeviceWaitIdle(device: ptr<u8>) -> i32;
extern "vulkan" fn vkDestroyDevice(device: ptr<u8>, allocator: ptr<u8>);
extern "vulkan" fn vkDestroyInstance(instance: ptr<u8>, allocator: ptr<u8>);
include "gpu_sys.rsx";

const VK_SUCCESS: i32 = 0;
const VK_STRUCTURE_TYPE_APPLICATION_INFO: u32 = 0;
const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO: u32 = 1;
const VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO: u32 = 2;
const VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO: u32 = 3;

const VK_API_VERSION_1_4: u32 = (1 << 22) | (4 << 12) | 0;

const VK_QUEUE_GRAPHICS_BIT: u32 = 1;
const VK_QUEUE_COMPUTE_BIT: u32 = 2;
const VK_QUEUE_TRANSFER_BIT: u32 = 4;

const VK_QUEUE_FAMILY_PROPERTIES_SIZE: i64 = 24;
const VK_FEATURES_BYTES: i64 = 220;

struct VkApplicationInfo {
    sType: u32,
    pNext: ptr<u8>,
    pApplicationName: ptr<u8>,
    applicationVersion: u32,
    pEngineName: ptr<u8>,
    engineVersion: u32,
    apiVersion: u32
}

struct VkInstanceCreateInfo {
    sType: u32,
    pNext: ptr<u8>,
    flags: u32,
    pApplicationInfo: ptr<u8>,
    enabledLayerCount: u32,
    ppEnabledLayerNames: ptr<ptr<u8>>,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ptr<ptr<u8>>
}

struct VkQueueFamilyProperties {
    queueFlags: u32,
    queueCount: u32,
    timestampValidBits: u32,
    minImageTransferGranularity: [f32; 3]
}

struct VkDeviceQueueCreateInfo {
    sType: u32,
    pNext: ptr<u8>,
    flags: u32,
    queueFamilyIndex: u32,
    queueCount: u32,
    pQueuePriorities: ptr<f32>
}

struct VkDeviceCreateInfo {
    sType: u32,
    pNext: ptr<u8>,
    flags: u32,
    queueCreateInfoCount: u32,
    pQueueCreateInfos: ptr<u8>,
    enabledLayerCount: u32,
    ppEnabledLayerNames: ptr<ptr<u8>>,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ptr<ptr<u8>>,
    pEnabledFeatures: ptr<u8>
}

fn vk_fail(where_str: ptr<u8>, rc: i32) {
    printf("vk: %s failed with %d\n", where_str, rc);
}

fn vk_create_instance() -> ptr<u8> {
    var app: VkApplicationInfo = zero(VkApplicationInfo);
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pNext = null;
    app.pApplicationName = "rsharp-vulkan" as ptr<u8>;
    app.applicationVersion = 1;
    app.pEngineName = "rsharp" as ptr<u8>;
    app.engineVersion = 1;
    app.apiVersion = VK_API_VERSION_1_4;
    var info: VkInstanceCreateInfo = zero(VkInstanceCreateInfo);
    info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    info.pNext = null;
    info.flags = 0;
    info.enabledLayerCount = 0;
    info.ppEnabledLayerNames = null;
    info.enabledExtensionCount = 0;
    info.ppEnabledExtensionNames = null;
    unsafe {
        info.pApplicationInfo = &app as ptr<u8>;
    }
    var instance: ptr<u8> = null;
    var rc: i32 = 1;
    unsafe {
        rc = vkCreateInstance(&info as ptr<u8>, null, &mut instance as ptr<ptr<u8>>);
    }
    if (rc != VK_SUCCESS) {
        vk_fail("vkCreateInstance" as ptr<u8>, rc);
        return null;
    }
    return instance;
}

fn vk_enumerate_physical(instance: ptr<u8>, max_dev: i64) -> (i32, ptr<ptr<u8>>) {
    var count: u32 = 0;
    var rc: i32 = 1;
    unsafe {
        rc = vkEnumeratePhysicalDevices(instance, &mut count as ptr<u32>, null);
    }
    if (rc != VK_SUCCESS || count == 0) {
        vk_fail("vkEnumeratePhysicalDevices" as ptr<u8>, rc);
        return (0, null);
    }
    var want: i64 = count as i64;
    if (want > max_dev) {
        want = max_dev;
    }
    let devs: ptr<ptr<u8>> = malloc((want as u64) * 8) as ptr<ptr<u8>>;
    if (devs == null) {
        return (0, null);
    }
    var got: u32 = want as u32;
    unsafe {
        rc = vkEnumeratePhysicalDevices(instance, &mut got as ptr<u32>, devs);
    }
    if (rc != VK_SUCCESS) {
        vk_fail("vkEnumeratePhysicalDevices" as ptr<u8>, rc);
        free(devs as ptr<u8>);
        return (0, null);
    }
    return (got as i32, devs);
}

fn vk_print_props(device: ptr<u8>) {
    let props: ptr<u8> = malloc(824);
    if (props == null) {
        printf("vk: out of memory\n");
        return;
    }
    unsafe {
        memset(props, 0, 824);
    }
    vkGetPhysicalDeviceProperties(device, props);
    var apiVersion: u32 = 0;
    var driverVersion: u32 = 0;
    var vendorID: u32 = 0;
    var deviceID: u32 = 0;
    var deviceType: u32 = 0;
    var name_s: [u8; 300] = [0];
    unsafe {
        let p: ptr<u32> = props as ptr<u32>;
        apiVersion = p[0];
        driverVersion = p[1];
        vendorID = p[2];
        deviceID = p[3];
        deviceType = p[4];
        let nb: ptr<u8> = props + 20;
        var i: i64 = 0;
        while (i < 256) {
            let b: u8 = nb[i];
            name_s[i] = b;
            if (b == 0) {
                break;
            }
            i += 1;
        }
    }
    var name: ptr<u8> = null;
    unsafe {
        name = &name_s[0] as ptr<u8>;
    }
    printf("vk: api %u.%u.%u\n", (apiVersion >> 22) & 0x3FF, (apiVersion >> 12) & 0x3FF, apiVersion & 0xFFF);
    printf("vk: driver %u\n", driverVersion);
    printf("vk: vendor 0x%x device 0x%x\n", vendorID, deviceID);
    printf("vk: deviceType %u\n", deviceType);
    printf("vk: device %s\n", name);
    free(props);
}

fn vk_get_queue_families(device: ptr<u8>) -> (i32, ptr<VkQueueFamilyProperties>) {
    var count: u32 = 0;
    unsafe {
        vkGetPhysicalDeviceQueueFamilyProperties(device, &mut count as ptr<u32>, null);
    }
    if (count == 0) {
        return (0, null);
    }
    let bytes: u64 = (count as u64) * (VK_QUEUE_FAMILY_PROPERTIES_SIZE as u64);
    let buf: ptr<u8> = malloc(bytes);
    if (buf == null) {
        return (0, null);
    }
    unsafe {
        memset(buf, 0, bytes);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &mut count as ptr<u32>, buf);
    }
    return (count as i32, buf as ptr<VkQueueFamilyProperties>);
}

fn vk_pick_graphics_family(device: ptr<u8>) -> i32 {
    let (count, props) = vk_get_queue_families(device);
    if (count <= 0 || props == null) {
        return 0 - 1;
    }
    var i: i64 = 0;
    var pick: i64 = 0 - 1;
    unsafe {
        while (i < count as i64) {
            let flags: u32 = props[i].queueFlags;
            if (pick < 0 && (flags & VK_QUEUE_GRAPHICS_BIT) != 0) {
                pick = i;
            }
            i += 1;
        }
        var j: i64 = 0;
        while (j < count as i64) {
            let flags: u32 = props[j].queueFlags;
            let queues: u32 = props[j].queueCount;
            let ts: u32 = props[j].timestampValidBits;
            printf("vk: queue family %lld flags 0x%x queues %u tsBits %u\n", j, flags, queues, ts);
            j += 1;
        }
    }
    free(props as ptr<u8>);
    return pick as i32;
}

fn vk_create_device(device: ptr<u8>, family: i32) -> ptr<u8> {
    if (family < 0) {
        return null;
    }
    var prio: [f32; 1] = [1.0];
    var qci: VkDeviceQueueCreateInfo = zero(VkDeviceQueueCreateInfo);
    qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    qci.pNext = null;
    qci.flags = 0;
    qci.queueFamilyIndex = family as u32;
    qci.queueCount = 1;
    unsafe {
        qci.pQueuePriorities = &prio[0] as ptr<f32>;
    }
    var ci: VkDeviceCreateInfo = zero(VkDeviceCreateInfo);
    ci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    ci.pNext = null;
    ci.flags = 0;
    ci.queueCreateInfoCount = 1;
    ci.enabledLayerCount = 0;
    ci.ppEnabledLayerNames = null;
    ci.enabledExtensionCount = 0;
    ci.ppEnabledExtensionNames = null;
    ci.pEnabledFeatures = null;
    unsafe {
        ci.pQueueCreateInfos = &qci as ptr<u8>;
    }
    var logical: ptr<u8> = null;
    var rc: i32 = 1;
    unsafe {
        rc = vkCreateDevice(device, &ci as ptr<u8>, null, &mut logical as ptr<ptr<u8>>);
    }
    if (rc != VK_SUCCESS) {
        vk_fail("vkCreateDevice" as ptr<u8>, rc);
        return null;
    }
    var queue: ptr<u8> = null;
    unsafe {
        vkGetDeviceQueue(logical, family as u32, 0, &mut queue as ptr<ptr<u8>>);
    }
    if (queue == null) {
        vkDestroyDevice(logical, null);
        printf("vk: vkGetDeviceQueue returned null\n");
        return null;
    }
    printf("vk: logical device created (family %d)\n", family);
    rc = vkDeviceWaitIdle(logical);
    if (rc != VK_SUCCESS) {
        vk_fail("vkDeviceWaitIdle" as ptr<u8>, rc);
        vkDestroyDevice(logical, null);
        return null;
    }
    printf("vk: device wait idle ok\n");
    vkDestroyDevice(logical, null);
    return logical;
}

fn vk_run_sample() -> i32 {
    var fails: i64 = 0;
    let instance: ptr<u8> = vk_create_instance();
    if (instance == null) {
        return 1;
    }
    let (count, devs) = vk_enumerate_physical(instance, 8);
    if (count <= 0 || devs == null) {
        vkDestroyInstance(instance, null);
        return 1;
    }
    printf("vk: %d physical device(s)\n", count);
    var i: i64 = 0;
    unsafe {
        while (i < count as i64) {
            let dev: ptr<u8> = devs[i];
            vk_print_props(dev);
            i += 1;
        }
    }
    var dev0: ptr<u8> = null;
    unsafe {
        dev0 = devs[0];
    }
    let family: i32 = vk_pick_graphics_family(dev0);
    if (family < 0) {
        printf("vk: no graphics queue family found\n");
        fails += 1;
    } else {
        let logical: ptr<u8> = vk_create_device(dev0, family);
        if (logical == null) {
            fails += 1;
        }
    }
    free(devs as ptr<u8>);
    vkDestroyInstance(instance, null);
    return fails as i32;
}
