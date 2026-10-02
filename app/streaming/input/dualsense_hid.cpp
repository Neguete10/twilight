#include "dualsense_hid.h"

DualSenseHidOutput::DualSenseHidOutput()
    : m_Impl(nullptr)
{
}

DualSenseHidOutput::~DualSenseHidOutput()
{
}

bool DualSenseHidOutput::send(const DualSenseOutputReport&, const char*)
{
    return false;
}
