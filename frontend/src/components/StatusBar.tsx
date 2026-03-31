import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  Modal,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../utils/theme';
import api from '../api/client';
import { LinearGradient } from 'expo-linear-gradient';

interface UserStatus {
  user_id: string;
  user_username: string;
  user_full_name: string;
  user_profile_image?: string;
  statuses: any[];
  has_unviewed: boolean;
}

interface StatusBarProps {
  currentUserId: string;
  onAddStatus?: () => void;
}

export default function StatusBar({ currentUserId, onAddStatus }: StatusBarProps) {
  const [userStatuses, setUserStatuses] = useState<UserStatus[]>([]);
  const [selectedStatus, setSelectedStatus] = useState<UserStatus | null>(null);
  const [currentStatusIndex, setCurrentStatusIndex] = useState(0);

  useEffect(() => {
    loadStatuses();
  }, []);

  const loadStatuses = async () => {
    try {
      const response = await api.get('/statuses');
      setUserStatuses(response.data);
    } catch (error) {
      console.log('Error loading statuses:', error);
    }
  };

  const viewStatus = async (userStatus: UserStatus) => {
    setSelectedStatus(userStatus);
    setCurrentStatusIndex(0);
    
    // Mark as viewed
    if (userStatus.statuses[0]) {
      try {
        await api.post(`/statuses/${userStatus.statuses[0].id}/view`);
      } catch (error) {
        console.log('Error marking status as viewed');
      }
    }
  };

  const nextStatus = async () => {
    if (!selectedStatus) return;
    
    if (currentStatusIndex < selectedStatus.statuses.length - 1) {
      const newIndex = currentStatusIndex + 1;
      setCurrentStatusIndex(newIndex);
      try {
        await api.post(`/statuses/${selectedStatus.statuses[newIndex].id}/view`);
      } catch (error) {
        console.log('Error marking status as viewed');
      }
    } else {
      setSelectedStatus(null);
    }
  };

  return (
    <View style={styles.container}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
      >
        {/* Add Status Button */}
        <TouchableOpacity style={styles.addStatus} onPress={onAddStatus}>
          <View style={styles.addButton}>
            <Ionicons name="add" size={24} color={colors.primary} />
          </View>
          <Text style={styles.statusLabel}>Your Story</Text>
        </TouchableOpacity>

        {/* User Statuses */}
        {userStatuses.map((userStatus) => (
          <TouchableOpacity
            key={userStatus.user_id}
            style={styles.statusItem}
            onPress={() => viewStatus(userStatus)}
          >
            <View style={[
              styles.statusRing,
              userStatus.has_unviewed ? styles.unviewedRing : styles.viewedRing
            ]}>
              {userStatus.user_profile_image ? (
                <Image
                  source={{ uri: userStatus.user_profile_image }}
                  style={styles.statusAvatar}
                />
              ) : (
                <View style={styles.statusAvatarPlaceholder}>
                  <Text style={styles.statusAvatarText}>
                    {userStatus.user_username[0].toUpperCase()}
                  </Text>
                </View>
              )}
            </View>
            <Text style={styles.statusLabel} numberOfLines={1}>
              {userStatus.user_id === currentUserId ? 'Your Story' : userStatus.user_username}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      {/* Status Viewer Modal */}
      <Modal
        visible={!!selectedStatus}
        animationType="fade"
        transparent={false}
        onRequestClose={() => setSelectedStatus(null)}
      >
        {selectedStatus && (
          <TouchableOpacity
            style={[styles.statusViewer, { backgroundColor: selectedStatus.statuses[currentStatusIndex]?.background_color || '#6366f1' }]}
            activeOpacity={1}
            onPress={nextStatus}
          >
            {/* Progress bars */}
            <View style={styles.progressContainer}>
              {selectedStatus.statuses.map((_, index) => (
                <View
                  key={index}
                  style={[
                    styles.progressBar,
                    index < currentStatusIndex && styles.progressComplete,
                    index === currentStatusIndex && styles.progressActive,
                  ]}
                />
              ))}
            </View>

            {/* Header */}
            <View style={styles.statusHeader}>
              <View style={styles.statusHeaderUser}>
                {selectedStatus.user_profile_image ? (
                  <Image
                    source={{ uri: selectedStatus.user_profile_image }}
                    style={styles.statusHeaderAvatar}
                  />
                ) : (
                  <View style={styles.statusHeaderAvatarPlaceholder}>
                    <Text style={styles.statusHeaderAvatarText}>
                      {selectedStatus.user_username[0].toUpperCase()}
                    </Text>
                  </View>
                )}
                <Text style={styles.statusHeaderName}>{selectedStatus.user_username}</Text>
              </View>
              <TouchableOpacity onPress={() => setSelectedStatus(null)}>
                <Ionicons name="close" size={28} color="white" />
              </TouchableOpacity>
            </View>

            {/* Content */}
            <View style={styles.statusContent}>
              {selectedStatus.statuses[currentStatusIndex]?.image ? (
                <Image
                  source={{ uri: selectedStatus.statuses[currentStatusIndex].image }}
                  style={styles.statusImage}
                  resizeMode="contain"
                />
              ) : (
                <Text style={styles.statusText}>
                  {selectedStatus.statuses[currentStatusIndex]?.content}
                </Text>
              )}
            </View>
          </TouchableOpacity>
        )}
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.background,
    paddingVertical: spacing.sm,
  },
  scrollContent: {
    paddingHorizontal: spacing.md,
  },
  addStatus: {
    alignItems: 'center',
    marginRight: spacing.md,
  },
  addButton: {
    width: 64,
    height: 64,
    borderRadius: 32,
    borderWidth: 2,
    borderColor: colors.primary,
    borderStyle: 'dashed',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.backgroundSecondary,
  },
  statusItem: {
    alignItems: 'center',
    marginRight: spacing.md,
  },
  statusRing: {
    width: 68,
    height: 68,
    borderRadius: 34,
    padding: 3,
    justifyContent: 'center',
    alignItems: 'center',
  },
  unviewedRing: {
    borderWidth: 3,
    borderColor: colors.accent,
  },
  viewedRing: {
    borderWidth: 2,
    borderColor: colors.borderLight,
  },
  statusAvatar: {
    width: 58,
    height: 58,
    borderRadius: 29,
  },
  statusAvatarPlaceholder: {
    width: 58,
    height: 58,
    borderRadius: 29,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  statusAvatarText: {
    color: colors.textInverse,
    fontSize: 22,
    fontWeight: '600',
  },
  statusLabel: {
    fontSize: 11,
    color: colors.textSecondary,
    marginTop: spacing.xs,
    maxWidth: 68,
    textAlign: 'center',
  },
  statusViewer: {
    flex: 1,
    paddingTop: 50,
  },
  progressContainer: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    marginBottom: spacing.sm,
  },
  progressBar: {
    flex: 1,
    height: 2,
    backgroundColor: 'rgba(255,255,255,0.3)',
    marginHorizontal: 2,
    borderRadius: 1,
  },
  progressComplete: {
    backgroundColor: 'white',
  },
  progressActive: {
    backgroundColor: 'white',
  },
  statusHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    marginBottom: spacing.md,
  },
  statusHeaderUser: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusHeaderAvatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    marginRight: spacing.sm,
  },
  statusHeaderAvatarPlaceholder: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.2)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: spacing.sm,
  },
  statusHeaderAvatarText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  statusHeaderName: {
    color: 'white',
    fontSize: 15,
    fontWeight: '600',
  },
  statusContent: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.xl,
  },
  statusText: {
    color: 'white',
    fontSize: 24,
    fontWeight: '600',
    textAlign: 'center',
    lineHeight: 34,
  },
  statusImage: {
    width: '100%',
    height: '80%',
  },
});
