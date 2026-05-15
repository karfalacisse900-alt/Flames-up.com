import React from 'react';
import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, layout } from '../../src/utils/theme';
import { Platform } from 'react-native';
import { appFontFamily } from '../../src/utils/typography';

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: colors.bgNav,
          borderTopColor: colors.divider,
          borderTopWidth: 0.5,
          height: Platform.OS === 'ios' ? 80 : 64,
          paddingTop: 8,
          paddingBottom: Platform.OS === 'ios' ? 22 : 8,
        },
        tabBarActiveTintColor: colors.textStrong,
        tabBarInactiveTintColor: colors.textHint,
        tabBarItemStyle: {
          minHeight: layout.minTouchTarget,
          paddingVertical: 2,
        },
        tabBarLabelStyle: {
          fontFamily: appFontFamily,
          fontSize: 11,
          fontWeight: '600',
          letterSpacing: 0,
        },
      }}
    >
      <Tabs.Screen
        name="home"
        options={{
          title: 'Home',
          tabBarIcon: ({ color, focused }) => (
            <Ionicons name={focused ? 'home' : 'home-outline'} size={22} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="places"
        options={{
          href: null,
        }}
      />
      <Tabs.Screen
        name="discover"
        options={{
          title: 'Discover',
          tabBarIcon: ({ color, focused }) => (
            <Ionicons name={focused ? 'compass' : 'compass-outline'} size={22} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="fashion"
        options={{
          href: null,
        }}
      />
      <Tabs.Screen
        name="profile"
        options={{
          title: 'Profile',
          tabBarIcon: ({ color, focused }) => (
            <Ionicons name={focused ? 'person' : 'person-outline'} size={22} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="messages"
        options={{
          href: null,
        }}
      />
    </Tabs>
  );
}
