import React, { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { appFontFamily } from '../utils/typography';
import { cleanCollectionName, DEFAULT_LIBRARY_COLLECTION } from '../utils/librarySave';
import { colors, hitSlop, layout, shadows } from '../utils/theme';

const PRESET_COLLECTIONS = [
  { name: DEFAULT_LIBRARY_COLLECTION, icon: 'albums-outline' },
  { name: 'Funny', icon: 'happy-outline' },
  { name: 'Inspiration', icon: 'sparkles-outline' },
  { name: 'Ideas', icon: 'bulb-outline' },
] as const;

type Props = {
  visible: boolean;
  saved?: boolean;
  saving?: boolean;
  onClose: () => void;
  onSave: (collection: string) => void;
  onUnsave?: () => void;
};

export default function SaveToCollectionModal({
  visible,
  saved = false,
  saving = false,
  onClose,
  onSave,
  onUnsave,
}: Props) {
  const [customName, setCustomName] = useState('');
  const cleanCustomName = useMemo(() => cleanCollectionName(customName), [customName]);
  const canAddCustom = customName.trim().length > 0;

  useEffect(() => {
    if (!visible) setCustomName('');
  }, [visible]);

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={s.overlay}>
        <Pressable style={StyleSheet.absoluteFillObject} onPress={onClose} />
        <Pressable style={s.card} onPress={() => {}}>
          <View style={s.header}>
            <View>
              <Text style={s.title}>Save</Text>
              <Text style={s.subtitle}>Add to My Library</Text>
            </View>
            <TouchableOpacity style={s.closeButton} onPress={onClose} activeOpacity={0.82} accessibilityRole="button" accessibilityLabel="Close save menu" hitSlop={hitSlop}>
              <Ionicons name="close" size={17} color={colors.textPrimary} />
            </TouchableOpacity>
          </View>

          <View style={s.presetList}>
            {PRESET_COLLECTIONS.map((item) => (
              <TouchableOpacity
                key={item.name}
                style={s.presetButton}
                onPress={() => onSave(item.name)}
                disabled={saving}
                activeOpacity={0.86}
              >
                <View style={s.presetIcon}>
                  <Ionicons name={item.icon} size={18} color={colors.textInverse} />
                </View>
                <Text style={s.presetText} numberOfLines={1}>{item.name}</Text>
              </TouchableOpacity>
            ))}
          </View>

          <View style={s.customRow}>
            <TextInput
              value={customName}
              onChangeText={setCustomName}
              placeholder="Custom collection"
              placeholderTextColor="#9A9A94"
              maxLength={36}
              style={s.customInput}
              returnKeyType="done"
              onSubmitEditing={() => canAddCustom && onSave(cleanCustomName)}
            />
            <TouchableOpacity
              style={[s.addButton, !canAddCustom && s.addButtonDisabled]}
              onPress={() => onSave(cleanCustomName)}
              disabled={!canAddCustom || saving}
              activeOpacity={0.86}
            >
              {saving && canAddCustom ? (
                <ActivityIndicator size="small" color={colors.textInverse} />
              ) : (
                <Ionicons name="add" size={20} color={colors.textInverse} />
              )}
            </TouchableOpacity>
          </View>

          {saved && onUnsave ? (
            <TouchableOpacity style={s.removeButton} onPress={onUnsave} disabled={saving} activeOpacity={0.84}>
              <Ionicons name="bookmark" size={17} color={colors.error} />
              <Text style={s.removeText}>Remove from Library</Text>
            </TouchableOpacity>
          ) : null}
        </Pressable>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const s = StyleSheet.create({
  overlay: {
    flex: 1,
    justifyContent: 'center',
    paddingHorizontal: 22,
    backgroundColor: colors.modalScrim,
  },
  card: {
    width: '100%',
    maxWidth: 312,
    alignSelf: 'center',
    borderRadius: 22,
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: 12,
    gap: 10,
    ...shadows.elevation2,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  title: {
    color: colors.textPrimary,
    fontFamily: appFontFamily,
    fontSize: 18,
    lineHeight: 23,
    fontWeight: '600',
  },
  subtitle: {
    color: colors.textHint,
    fontFamily: appFontFamily,
    fontSize: 12,
    lineHeight: 16,
    fontWeight: '500',
    marginTop: 1,
  },
  closeButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    backgroundColor: colors.bgSubtle,
    alignItems: 'center',
    justifyContent: 'center',
  },
  presetList: { gap: 7 },
  presetButton: {
    width: '100%',
    minHeight: layout.minTouchTarget,
    borderRadius: 15,
    backgroundColor: colors.surfaceSoft,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    paddingHorizontal: 9,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  presetIcon: {
    width: 29,
    height: 29,
    borderRadius: 15,
    backgroundColor: colors.accentPrimary,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1.2,
    borderColor: colors.accentPrimaryHover,
  },
  presetText: {
    flex: 1,
    minWidth: 0,
    color: colors.textPrimary,
    fontFamily: appFontFamily,
    fontSize: 13,
    lineHeight: 17,
    fontWeight: '600',
  },
  customRow: {
    minHeight: 46,
    borderRadius: 15,
    backgroundColor: colors.bgSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    paddingLeft: 12,
    paddingRight: 6,
    gap: 7,
  },
  customInput: {
    flex: 1,
    minWidth: 0,
    color: colors.textPrimary,
    fontFamily: appFontFamily,
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '500',
    paddingVertical: 8,
  },
  addButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    backgroundColor: colors.accentPrimary,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1.2,
    borderColor: colors.accentPrimaryHover,
  },
  addButtonDisabled: {
    opacity: 0.45,
  },
  removeButton: {
    height: 40,
    borderRadius: 14,
    backgroundColor: '#FFF0F2',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  removeText: {
    color: colors.error,
    fontFamily: appFontFamily,
    fontSize: 13,
    lineHeight: 17,
    fontWeight: '600',
  },
});
