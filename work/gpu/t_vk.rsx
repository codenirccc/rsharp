include "../../modules/gpu/vk.rsx";

fn main() -> i32 {
    let rc: i32 = vk_run_sample();
    if (rc == 0) {
        printf("vulkan suite: ok\n");
        return 0;
    }
    printf("vulkan suite: FAIL %d\n", rc);
    return 1;
}
