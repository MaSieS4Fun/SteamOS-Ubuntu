// MasiScript: minimal Renderer stub so YabauseThread links without Vulkan.
#include <cstddef>

#ifndef VK_NULL_HANDLE
#define VK_NULL_HANDLE nullptr
#endif

class Window;

class Renderer {
 public:
  Renderer() = default;
  ~Renderer() = default;
  void* GetVulkanQueue() const { return VK_NULL_HANDLE; }
  void* GetVulkanDevice() const { return VK_NULL_HANDLE; }
  Window* getWindow() const { return nullptr; }
  void* OpenWindow(int, int, const char*, void*) { return nullptr; }
};

extern "C" {
void vkQueueWaitIdle(void*) {}
void vkDeviceWaitIdle(void*) {}
}

Renderer* _vulkanRenderer = nullptr;
