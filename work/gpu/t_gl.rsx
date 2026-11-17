include "../../modules/gpu/gl.rsx";

fn main() -> i32 {
    let rc: i32 = glx_sample();
    if (rc == 0) {
        printf("opengl suite: ok\n");
        return 0;
    }
    printf("opengl suite: FAIL %d\n", rc);
    return 1;
}
