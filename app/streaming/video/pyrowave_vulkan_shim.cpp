// Generated wrapper. Do not include pyrowave_vulkan_rename.h here.
// Links only libpyrowave-shared, so these calls do not bind to the Metal library.
#define VK_ENABLE_BETA_EXTENSIONS
#include <vulkan/vulkan.h>
#include <pyrowave.h>

extern "C" {

void twilight_vkpw_pyrowave_get_api_version(uint32_t *major, uint32_t *minor, uint32_t *patch)
{
    pyrowave_get_api_version(major, minor, patch);
}

pyrowave_result twilight_vkpw_pyrowave_create_default_device(pyrowave_device *device)
{
    return pyrowave_create_default_device(device);
}

pyrowave_result twilight_vkpw_pyrowave_create_device(const pyrowave_device_create_info *info, pyrowave_device *device)
{
    return pyrowave_create_device(info, device);
}

pyrowave_result twilight_vkpw_pyrowave_create_device_by_compat( uint32_t vid, uint32_t pid, const pyrowave_uuid *device_uuid, const pyrowave_uuid *driver_uuid, const pyrowave_luid *device_luid, pyrowave_device *device)
{
    return pyrowave_create_device_by_compat(vid, pid, device_uuid, driver_uuid, device_luid, device);
}

void twilight_vkpw_pyrowave_device_report_performance_stats(pyrowave_device device, pyrowave_message_cb cb, void *userdata, bool reset)
{
    pyrowave_device_report_performance_stats(device, cb, userdata, reset);
}

void twilight_vkpw_pyrowave_device_get_vk_device_handles( pyrowave_device device, VkInstance *vk_instance, VkPhysicalDevice *vk_physical_device, VkDevice *vk_device)
{
    pyrowave_device_get_vk_device_handles(device, vk_instance, vk_physical_device, vk_device);
}

void twilight_vkpw_pyrowave_device_set_command_buffer(pyrowave_device device, VkCommandBuffer cmd)
{
    pyrowave_device_set_command_buffer(device, cmd);
}

pyrowave_result twilight_vkpw_pyrowave_device_set_queue_type(pyrowave_device device, VkQueueFlagBits queue_flags)
{
    return pyrowave_device_set_queue_type(device, queue_flags);
}

bool twilight_vkpw_pyrowave_device_confirm_interop_support(pyrowave_device device)
{
    return pyrowave_device_confirm_interop_support(device);
}

void twilight_vkpw_pyrowave_device_destroy(pyrowave_device device)
{
    pyrowave_device_destroy(device);
}

pyrowave_result twilight_vkpw_pyrowave_sync_object_create(const pyrowave_sync_object_create_info *info, pyrowave_sync_object *sync)
{
    return pyrowave_sync_object_create(info, sync);
}

VkSemaphore twilight_vkpw_pyrowave_sync_object_get_semaphore(pyrowave_sync_object sync)
{
    return pyrowave_sync_object_get_semaphore(sync);
}

pyrowave_result twilight_vkpw_pyrowave_sync_object_export_handle(pyrowave_sync_object sync, pyrowave_os_handle *handle)
{
    return pyrowave_sync_object_export_handle(sync, handle);
}

pyrowave_result twilight_vkpw_pyrowave_sync_object_cpu_wait(pyrowave_sync_object sync, uint64_t value, uint64_t timeout)
{
    return pyrowave_sync_object_cpu_wait(sync, value, timeout);
}

pyrowave_result twilight_vkpw_pyrowave_sync_object_cpu_signal(pyrowave_sync_object sync, uint64_t value)
{
    return pyrowave_sync_object_cpu_signal(sync, value);
}

void twilight_vkpw_pyrowave_sync_object_destroy(pyrowave_sync_object sync)
{
    pyrowave_sync_object_destroy(sync);
}

pyrowave_result twilight_vkpw_pyrowave_image_create(const pyrowave_image_create_info *info, pyrowave_image *image)
{
    return pyrowave_image_create(info, image);
}

VkImage twilight_vkpw_pyrowave_image_get_handle(pyrowave_image image)
{
    return pyrowave_image_get_handle(image);
}

pyrowave_result twilight_vkpw_pyrowave_image_get_image_view(pyrowave_image image, VkImageAspectFlagBits aspect, VkImageUsageFlagBits usage, pyrowave_image_view *view)
{
    return pyrowave_image_get_image_view(image, aspect, usage, view);
}

void twilight_vkpw_pyrowave_image_destroy(pyrowave_image image)
{
    pyrowave_image_destroy(image);
}

pyrowave_result twilight_vkpw_pyrowave_encoder_create(const pyrowave_encoder_create_info *info, pyrowave_encoder *encoder)
{
    return pyrowave_encoder_create(info, encoder);
}

pyrowave_result twilight_vkpw_pyrowave_encoder_encode_gpu_synchronous(pyrowave_encoder encoder, const pyrowave_gpu_sync_operation *acquire, const pyrowave_gpu_sync_operation *release, const pyrowave_gpu_buffers *buffers, const pyrowave_rate_control *rate_control)
{
    return pyrowave_encoder_encode_gpu_synchronous(encoder, acquire, release, buffers, rate_control);
}

pyrowave_result twilight_vkpw_pyrowave_encoder_encode_cpu_synchronous(pyrowave_encoder encoder, const pyrowave_cpu_buffer *buffers, const pyrowave_rate_control *rate_control)
{
    return pyrowave_encoder_encode_cpu_synchronous(encoder, buffers, rate_control);
}

pyrowave_result twilight_vkpw_pyrowave_encoder_compute_num_packets(pyrowave_encoder encoder, size_t packet_boundary, size_t *num_packets)
{
    return pyrowave_encoder_compute_num_packets(encoder, packet_boundary, num_packets);
}

pyrowave_result twilight_vkpw_pyrowave_encoder_packetize(pyrowave_encoder encoder, pyrowave_packet *packets, size_t packet_boundary, size_t *out_packets, void *bitstream, size_t size)
{
    return pyrowave_encoder_packetize(encoder, packets, packet_boundary, out_packets, bitstream, size);
}

void twilight_vkpw_pyrowave_encoder_destroy(pyrowave_encoder encoder)
{
    pyrowave_encoder_destroy(encoder);
}

bool twilight_vkpw_pyrowave_decoder_device_prefers_fragment_path(pyrowave_device device)
{
    return pyrowave_decoder_device_prefers_fragment_path(device);
}

pyrowave_result twilight_vkpw_pyrowave_decoder_create(const pyrowave_decoder_create_info *info, pyrowave_decoder *decoder)
{
    return pyrowave_decoder_create(info, decoder);
}

void twilight_vkpw_pyrowave_decoder_clear(pyrowave_decoder decoder)
{
    pyrowave_decoder_clear(decoder);
}

pyrowave_result twilight_vkpw_pyrowave_decoder_push_packet(pyrowave_decoder decoder, const void *data, size_t size)
{
    return pyrowave_decoder_push_packet(decoder, data, size);
}

bool twilight_vkpw_pyrowave_decoder_decode_is_ready(pyrowave_decoder decoder, bool allow_partial_frame)
{
    return pyrowave_decoder_decode_is_ready(decoder, allow_partial_frame);
}

pyrowave_result twilight_vkpw_pyrowave_decoder_decode_gpu_buffer(pyrowave_decoder decoder, const pyrowave_gpu_sync_operation *acquire, const pyrowave_gpu_sync_operation *release, const pyrowave_gpu_buffers *buffers)
{
    return pyrowave_decoder_decode_gpu_buffer(decoder, acquire, release, buffers);
}

pyrowave_result twilight_vkpw_pyrowave_decoder_decode_cpu_buffer_synchronous(pyrowave_decoder decoder, const pyrowave_cpu_buffer *buffers)
{
    return pyrowave_decoder_decode_cpu_buffer_synchronous(decoder, buffers);
}

void twilight_vkpw_pyrowave_decoder_destroy(pyrowave_decoder decoder)
{
    pyrowave_decoder_destroy(decoder);
}

}  // extern "C"
