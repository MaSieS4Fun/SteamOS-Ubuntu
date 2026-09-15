// MasiScript: Qt Vulkan widget no-op for OpenGL-only Linux builds.
#include "QYabVulkanWidget.h"
#include <QResizeEvent>

QYabVulkanWidget* QYabVulkanWidget::_instance = nullptr;

QYabVulkanWidget::QYabVulkanWidget(QWidget* parent) : QWidget(parent) {
  _instance = this;
  pYabauseThread = nullptr;
}

QYabVulkanWidget::~QYabVulkanWidget() = default;

QPaintEngine* QYabVulkanWidget::paintEngine() const { return nullptr; }

void QYabVulkanWidget::ready() {}

void QYabVulkanWidget::paintEvent(QPaintEvent*) {}

void QYabVulkanWidget::resizeEvent(QResizeEvent* event) {
  QWidget::resizeEvent(event);
}

void QYabVulkanWidget::updateView(const QSize&) {}
