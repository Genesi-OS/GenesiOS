# Plasma 6 QML KCM.
#
# kcmutils_add_qml_kcm() is the documented path: it creates the plugin target,
# bundles everything under ui/ as QML resources, and installs into the
# plasma/kcms/systemsettings namespace so System Settings finds it. There is no
# pure-QML alternative in Plasma 6 -- KQuickConfigModule is the base class for
# every QML KCM -- which is why this package carries C++ at all.
cmake_minimum_required(VERSION 3.20)

project(kcm_genesi_update VERSION 1.0.0)

set(QT_MIN_VERSION 6.6.0)
set(KF_MIN_VERSION 6.0.0)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${ECM_KDE_MODULE_DIR})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS
    CoreAddons
    I18n
    KCMUtils
)

kcmutils_add_qml_kcm(kcm_genesi_update)

target_sources(kcm_genesi_update PRIVATE
    kcmgenesiupdate.cpp
)

target_link_libraries(kcm_genesi_update PRIVATE
    Qt6::Core
    Qt6::Quick
    KF6::CoreAddons
    KF6::I18n
    KF6::KCMUtils
)
