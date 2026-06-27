<template>
  <div
    class="chat-shell"
    :class="{ 'has-active': activeConversationId, 'is-dragging': isDragging }"
    @dragenter.prevent="onDragEnter"
    @dragover.prevent="onDragOver"
    @dragleave.prevent="onDragLeave"
    @drop.prevent="handleDrop"
  >
    <div v-if="isDragging" class="drop-overlay">
      <UploadCloud :size="42" />
      <strong>Thả tệp hoặc thư mục vào đây</strong>
      <span>Hệ thống sẽ giữ nguyên cấu trúc thư mục khi trình duyệt cho phép.</span>
    </div>

    <div class="notification-stack">
      <button
        v-for="notification in toastNotifications"
        :key="notification.id"
        class="message-toast"
        type="button"
        @click="openNotification(notification)"
      >
        <el-avatar :size="34" :src="notification.avatar || undefined">
          {{ initials(notification.title) }}
        </el-avatar>
        <span>
          <strong>{{ notification.title }}</strong>
          <small>{{ notification.body }}</small>
        </span>
        <X :size="15" @click.stop="dismissNotification(notification.id)" />
      </button>
    </div>

    <nav class="app-rail">
      <div class="rail-logo">
        <img src="@/assets/Logo.png" alt="YS" />
      </div>

      <div class="rail-actions">
        <el-tooltip content="Tin nhắn" placement="right">
          <button class="rail-button" :class="{ active: panelMode === 'chats' }" type="button" @click="setPanelMode('chats')">
            <MessageCircle :size="22" />
          </button>
        </el-tooltip>
        <el-tooltip content="Danh bạ" placement="right">
          <button class="rail-button" :class="{ active: panelMode === 'contacts' }" type="button" @click="setPanelMode('contacts')">
            <Users :size="22" />
          </button>
        </el-tooltip>
      </div>

      <div class="rail-bottom">
        <el-tooltip content="Cài đặt hồ sơ" placement="right">
          <button class="rail-button profile-rail-button" type="button" @click="openProfileDialog">
            <el-avatar :size="30" :src="currentUser.avatar || undefined">
              {{ initials(currentUser.fullname || currentUser.userid) }}
            </el-avatar>
          </button>
        </el-tooltip>
        <el-tooltip content="Đăng xuất" placement="right">
          <button class="rail-button" type="button" @click="handleLogout">
            <LogOut :size="22" />
          </button>
        </el-tooltip>
      </div>
    </nav>

    <aside class="conversation-panel">
      <header class="panel-header">
        <div>
          <p class="eyebrow">YS Chat</p>
          <h1>{{ panelTitle }}</h1>
        </div>
        <div class="panel-actions">
          <el-tooltip content="Thêm liên hệ" placement="bottom">
            <button class="icon-button" type="button" @click="openContactDialog">
              <UserPlus :size="20" />
            </button>
          </el-tooltip>
          <el-tooltip content="Tạo nhóm" placement="bottom">
            <button class="icon-button primary" type="button" @click="openGroupDialog">
              <Users :size="20" />
            </button>
          </el-tooltip>
        </div>
      </header>

      <div class="search-box">
        <Search :size="18" />
        <input v-model="searchKeyword" type="search" placeholder="Tìm theo tên hoặc số thẻ" />
      </div>

      <div v-if="hasSearchKeyword" class="search-results">
        <section v-if="filteredConversations.length" class="result-section">
          <div class="result-title">Hội thoại</div>
          <button
            v-for="conversation in filteredConversations"
            :key="conversation.id"
            class="conversation-item"
            :class="{
              active: conversation.id === activeConversationId,
              'has-unread': unreadCount(conversation.id),
            }"
            type="button"
            @click="selectConversation(conversation)"
          >
            <div v-if="conversation.type === 'group' && !conversation.avatar" class="conversation-avatar group">
              <Users :size="22" />
              <span>{{ conversation.memberCount }}</span>
            </div>
            <el-avatar v-else class="conversation-avatar" :size="44" :src="conversation.avatar || undefined">
              {{ initials(conversation.name) }}
            </el-avatar>
            <div class="conversation-main">
              <div class="conversation-top">
                <span class="conversation-name">{{ conversation.name }}</span>
                <div class="conversation-meta">
                  <time>{{ conversationTime(conversation) }}</time>
                  <span v-if="unreadCount(conversation.id)" class="unread-badge">
                    {{ formatUnreadCount(conversation.id) }}
                  </span>
                </div>
              </div>
              <p>{{ lastMessagePreview(conversation) }}</p>
            </div>
          </button>
        </section>

        <section class="result-section">
          <div class="result-title">Người dùng</div>
          <div v-if="searchingUsers" class="list-state compact">Đang tìm...</div>
          <template v-else-if="searchedUsers.length">
            <div v-for="user in searchedUsers" :key="user.userid" class="user-result">
              <el-avatar :size="40" :src="user.avatar || undefined">
                {{ initials(user.fullname || user.userid) }}
              </el-avatar>
              <div class="user-result-main">
                <strong>{{ user.fullname || user.userid }}</strong>
                <span>{{ user.userid }}</span>
              </div>
              <button
                v-if="user.isContact"
                class="result-action ghost"
                type="button"
                @click="startDirectChat(user.userid)"
              >
                Nhắn tin
              </button>
              <button
                v-else
                class="result-action"
                type="button"
                @click="addContactFromUser(user)"
              >
                Thêm
              </button>
            </div>
          </template>
        </section>

        <div v-if="!searchingUsers && !filteredConversations.length && !searchedUsers.length" class="empty-list">
          <Search :size="28" />
          <span>Không tìm thấy kết quả</span>
        </div>
      </div>

      <template v-else-if="panelMode === 'contacts'">
        <div v-if="loadingContacts" class="list-state">Đang tải danh bạ...</div>
        <div v-else-if="contacts.length === 0" class="empty-list">
          <Users :size="28" />
          <span>Danh bạ chưa có liên hệ</span>
        </div>
        <div v-else class="conversation-list contact-list">
          <button
            v-for="contact in contacts"
            :key="contact.userid"
            class="conversation-item contact-item"
            type="button"
            @click="startDirectChat(contact.userid)"
          >
            <el-avatar class="conversation-avatar" :size="44" :src="contact.avatar || undefined">
              {{ initials(contact.fullname || contact.userid) }}
            </el-avatar>
            <div class="conversation-main">
              <div class="conversation-top">
                <span class="conversation-name">{{ contact.fullname || contact.userid }}</span>
              </div>
              <p>{{ contact.userid }}</p>
            </div>
          </button>
        </div>
      </template>

      <template v-else>
        <div v-if="loadingConversations" class="list-state">Đang tải...</div>
        <div v-else-if="filteredConversations.length === 0" class="empty-list">
          <MessageCircle :size="28" />
          <span>Chưa có hội thoại</span>
        </div>

        <div v-else class="conversation-list">
          <button
            v-for="conversation in filteredConversations"
            :key="conversation.id"
            class="conversation-item"
            :class="{
              active: conversation.id === activeConversationId,
              'has-unread': unreadCount(conversation.id),
            }"
            type="button"
            @click="selectConversation(conversation)"
          >
            <div v-if="conversation.type === 'group' && !conversation.avatar" class="conversation-avatar group">
              <Users :size="22" />
              <span>{{ conversation.memberCount }}</span>
            </div>
            <el-avatar v-else class="conversation-avatar" :size="44" :src="conversation.avatar || undefined">
              {{ initials(conversation.name) }}
            </el-avatar>
            <div class="conversation-main">
              <div class="conversation-top">
                <span class="conversation-name">{{ conversation.name }}</span>
                <div class="conversation-meta">
                  <time>{{ conversationTime(conversation) }}</time>
                  <span v-if="unreadCount(conversation.id)" class="unread-badge">
                    {{ formatUnreadCount(conversation.id) }}
                  </span>
                </div>
              </div>
              <p>{{ lastMessagePreview(conversation) }}</p>
            </div>
          </button>
        </div>
      </template>
    </aside>

    <main class="chat-pane">
      <template v-if="activeConversation">
        <header class="chat-header">
          <button class="mobile-back" type="button" @click="activeConversationId = null">
            <ChevronLeft :size="22" />
          </button>
          <el-avatar :size="44" :src="activeConversation.avatar || undefined">
            {{ initials(activeConversation.name) }}
          </el-avatar>
          <div class="chat-title">
            <h2>{{ activeConversation.name }}</h2>
            <span>{{ activeConversation.memberCount }} thành viên</span>
          </div>
          <div v-if="activeConversation.type === 'group'" class="chat-actions">
            <el-tooltip content="Thêm thành viên" placement="bottom">
              <button class="icon-button" type="button" @click="openAddMemberDialog">
                <UserPlus :size="20" />
              </button>
            </el-tooltip>
          </div>
        </header>

        <section ref="messageListRef" class="message-list" :style="messageListStyle">
          <div v-if="loadingMessages" class="message-state">Đang tải tin nhắn...</div>
          <div v-else-if="messages.length === 0" class="message-state">
            <MessageCircle :size="34" />
            <span>Bắt đầu cuộc trò chuyện</span>
          </div>

          <div
            v-for="message in messages"
            v-else
            :id="`message-${message.id}`"
            :key="message.id"
            class="message-row"
            :class="{ own: isOwnMessage(message) }"
          >
            <el-avatar
              v-if="!isOwnMessage(message)"
              :size="32"
              :src="message.senderAvatar || undefined"
            >
              {{ initials(message.senderName) }}
            </el-avatar>

            <div class="message-stack">
              <span
                v-if="activeConversation.type === 'group' && !isOwnMessage(message)"
                class="sender-name"
              >
                {{ message.senderName }}
              </span>

              <div class="message-bubble" :class="message.type">
                <button
                  v-if="message.replyTo"
                  class="reply-reference"
                  type="button"
                  @click="scrollToMessage(message.replyTo.id)"
                >
                  <strong>{{ message.replyTo.senderName }}</strong>
                  <span>{{ messageReferencePreview(message.replyTo) }}</span>
                </button>

                <div v-if="message.forwardedFrom" class="forwarded-label">
                  <Forward :size="13" />
                  <span>Chuyển tiếp từ {{ message.forwardedFrom.senderName }}</span>
                </div>

                <a
                  v-if="message.type === 'link'"
                  class="message-link"
                  :href="safeLink(message.content)"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <Link2 :size="16" />
                  <span>{{ message.content }}</span>
                </a>

                <p v-else-if="message.content" class="message-text">
                  <span
                    v-for="(part, index) in messageTextParts(message.content)"
                    :key="`${message.id}-${index}`"
                    :class="{ mention: part.isMention }"
                  >
                    {{ part.text }}
                  </span>
                </p>

                <div v-if="imageAttachments(message).length" class="image-grid">
                  <a
                    v-for="attachment in imageAttachments(message)"
                    :key="attachment.id || attachment.fileUrl"
                    :href="attachment.fileUrl"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    <img :src="attachment.fileUrl" :alt="attachment.fileName" loading="lazy" />
                  </a>
                </div>

                <div v-if="voiceAttachments(message).length" class="voice-list">
                  <div
                    v-for="attachment in voiceAttachments(message)"
                    :key="attachment.id || attachment.fileUrl"
                    class="voice-player"
                  >
                    <div class="voice-icon">
                      <FileAudio :size="18" />
                    </div>
                    <audio controls preload="metadata" :src="attachment.fileUrl"></audio>
                    <a
                      class="download-button"
                      :href="attachment.fileUrl"
                      :download="downloadFileName(attachment)"
                      target="_blank"
                      rel="noopener noreferrer"
                      title="Tải về"
                    >
                      <Download :size="16" />
                    </a>
                  </div>
                </div>

                <div v-if="fileAttachments(message).length" class="attachment-list">
                  <div
                    v-for="attachment in fileAttachments(message)"
                    :key="attachment.id || attachment.fileUrl"
                    class="attachment-item"
                    :class="fileKind(attachment, message.type)"
                  >
                    <div class="attachment-icon">
                      <component :is="fileIcon(attachment, message.type)" :size="19" />
                      <small v-if="fileBadge(attachment, message.type)" class="attachment-badge">
                        {{ fileBadge(attachment, message.type) }}
                      </small>
                    </div>
                    <div class="attachment-meta">
                      <a :href="attachment.fileUrl" target="_blank" rel="noopener noreferrer">
                        {{ attachment.relativePath || attachment.fileName }}
                      </a>
                      <span>
                        {{ fileKindLabel(attachment, message.type) }} · {{ formatBytes(attachment.fileSize) }}
                      </span>
                    </div>
                    <a
                      class="download-button"
                      :href="attachment.fileUrl"
                      :download="downloadFileName(attachment)"
                      target="_blank"
                      rel="noopener noreferrer"
                      title="Tải về"
                    >
                      <Download :size="16" />
                    </a>
                  </div>
                </div>

                <time>{{ formatTime(message.createdAt) }}</time>
              </div>
              <div class="message-actions">
                <el-tooltip content="Trả lời" placement="top">
                  <button type="button" @click="startReply(message)">
                    <Reply :size="15" />
                  </button>
                </el-tooltip>
                <el-tooltip content="Chuyển tiếp" placement="top">
                  <button type="button" @click="openForwardDialog(message)">
                    <Forward :size="15" />
                  </button>
                </el-tooltip>
              </div>
            </div>
          </div>
        </section>

        <footer class="composer">
          <div v-if="replyingTo" class="reply-compose">
            <Reply :size="17" />
            <div>
              <strong>Trả lời {{ replyingTo.senderName }}</strong>
              <span>{{ messageReferencePreview(replyingTo) }}</span>
            </div>
            <button type="button" @click="cancelReply">
              <X :size="15" />
            </button>
          </div>

          <div v-if="pendingAttachments.length" class="pending-files">
            <div
              v-for="attachment in pendingAttachments"
              :key="attachment.fileUrl"
              class="pending-file"
              :class="fileKind(attachment, pendingAttachmentType)"
            >
              <component :is="fileIcon(attachment, pendingAttachmentType)" :size="16" />
              <span>{{ attachment.relativePath || attachment.fileName }}</span>
              <small>{{ fileKindLabel(attachment, pendingAttachmentType) }}</small>
              <button type="button" @click="removePendingAttachment(attachment.fileUrl)">
                <X :size="14" />
              </button>
            </div>
          </div>

          <div v-if="isRecording" class="voice-recording">
            <span class="record-dot"></span>
            <strong>{{ recordingDurationLabel }}</strong>
            <span>Dang ghi am</span>
            <button type="button" aria-label="Huy ghi am" @click="cancelVoiceRecording">
              <X :size="16" />
            </button>
          </div>

          <div class="composer-body">
            <div class="composer-tools">
              <el-tooltip content="Gửi tệp" placement="top">
                <button class="tool-button" type="button" :disabled="isRecording" @click="fileInputRef?.click()">
                  <Paperclip :size="20" />
                </button>
              </el-tooltip>
              <el-tooltip content="Gửi thư mục" placement="top">
                <button class="tool-button" type="button" :disabled="isRecording" @click="folderInputRef?.click()">
                  <FolderUp :size="20" />
                </button>
              </el-tooltip>
              <el-tooltip :content="isRecording ? 'Dung va gui voice' : 'Ghi voice'" placement="top">
                <button
                  class="tool-button voice-record-button"
                  :class="{ active: isRecording, recording: isRecording }"
                  type="button"
                  :disabled="!isRecording && (sending || uploading || preparingRecording)"
                  @click="toggleVoiceRecording"
                >
                  <Square v-if="isRecording" :size="18" />
                  <Mic v-else :size="20" />
                </button>
              </el-tooltip>
            </div>

            <div class="composer-input-wrap">
              <div v-if="mentionActive && mentionSuggestions.length" class="mention-menu">
                <button
                  v-for="(member, index) in mentionSuggestions"
                  :key="member.userid"
                  :class="{ selected: index === mentionSelectedIndex }"
                  type="button"
                  @mousedown.prevent="insertMention(member)"
                >
                  <el-avatar :size="28" :src="member.avatar || undefined">
                    {{ initials(displayName(member)) }}
                  </el-avatar>
                  <span>
                    <strong>{{ displayName(member) }}</strong>
                    <small>{{ member.userid }}</small>
                  </span>
                </button>
              </div>

              <textarea
                ref="composerInputRef"
                v-model="composerText"
                rows="1"
                placeholder="Nhập tin nhắn, dùng @ để tag tên"
                @input="updateMentionState"
                @click="updateMentionState"
                @keyup="updateMentionState"
                @keydown.down="handleMentionArrow($event, 1)"
                @keydown.up="handleMentionArrow($event, -1)"
                @keydown.tab="handleMentionTab"
                @keydown.enter.exact.prevent="handleComposerEnter"
                @keydown.esc="closeMentionMenu"
              ></textarea>
            </div>

            <button
              class="send-button"
              type="button"
              :disabled="sending || uploading || isRecording"
              @click="sendCurrentMessage"
            >
              <SendHorizontal :size="20" />
            </button>
          </div>

          <input
            ref="fileInputRef"
            hidden
            multiple
            type="file"
            @change="handleFilesSelected($event, 'file')"
          />
          <input
            ref="folderInputRef"
            hidden
            multiple
            directory
            webkitdirectory
            type="file"
            @change="handleFilesSelected($event, 'folder')"
          />
        </footer>
      </template>

      <section v-else class="empty-chat">
        <div class="welcome-copy">
          <img class="welcome-logo" src="@/assets/Logo.png" alt="YS Chat" />
          <h2>Chào mừng đến với YS Chat</h2>
          <p>Chọn một hội thoại ở danh sách bên trái để bắt đầu nhắn tin.</p>
        </div>
        <MessageCircle :size="44" />
        <h2>Chọn một hội thoại</h2>
        <p>Nhập số thẻ để chat riêng hoặc tạo nhóm nội bộ.</p>
      </section>
    </main>

    <aside class="info-panel" v-if="activeConversation">
      <div class="profile-block">
        <div
          v-if="activeConversation.type === 'group'"
          class="conversation-cover"
          :class="{ empty: !activeConversation.background }"
        >
          <img v-if="activeConversation.background" :src="activeConversation.background" alt="" />
          <button
            v-if="isCurrentUserGroupOwner"
            class="cover-upload-button"
            type="button"
            @click="groupBackgroundInputRef?.click()"
          >
            <Camera :size="15" />
          </button>
        </div>
        <div class="conversation-avatar-editor" :class="{ 'with-cover': activeConversation.type === 'group' }">
          <el-avatar :size="72" :src="activeConversation.avatar || undefined">
          {{ initials(activeConversation.name) }}
          </el-avatar>
          <button
            v-if="isCurrentUserGroupOwner"
            class="avatar-upload-button mini"
            type="button"
            @click="groupAvatarInputRef?.click()"
          >
            <Camera :size="15" />
          </button>
        </div>
        <h3>{{ activeConversation.name }}</h3>
        <input
          ref="groupAvatarInputRef"
          hidden
          accept="image/*"
          type="file"
          @change="handleGroupImageSelected($event, 'avatar')"
        />
        <input
          ref="groupBackgroundInputRef"
          hidden
          accept="image/*"
          type="file"
          @change="handleGroupImageSelected($event, 'background')"
        />
        <span>{{ activeConversation.memberCount }} thành viên</span>
      </div>

      <section class="info-section">
        <div class="section-title">
          <h4>Thành viên nhóm</h4>
          <button v-if="activeConversation.type === 'group'" type="button" @click="openAddMemberDialog">
            <UserPlus :size="16" />
          </button>
        </div>
        <button
          v-if="activeConversation.type === 'group'"
          class="member-count-button"
          type="button"
          @click="membersExpanded = !membersExpanded"
        >
          <Users :size="20" />
          <strong>{{ activeConversation.memberCount }} thành viên</strong>
        </button>
        <div v-if="activeConversation.type !== 'group' || membersExpanded" class="member-list">
          <div v-for="member in activeConversation.members" :key="member.userid" class="member-item">
            <el-avatar :size="32" :src="member.avatar || undefined">
              {{ initials(displayName(member)) }}
            </el-avatar>
            <div class="member-meta">
              <strong>{{ displayName(member) }}</strong>
              <span>{{ member.nickname && member.fullname ? `${member.fullname} · ${member.userid}` : member.userid }}</span>
            </div>
            <el-tooltip content="Đặt biệt danh" placement="left">
              <button
                class="member-action-button"
                type="button"
                :aria-label="`Đặt biệt danh cho ${member.fullname || member.userid}`"
                @click="openNicknameDialog(member)"
              >
                <Pencil :size="15" />
              </button>
            </el-tooltip>
            <el-tooltip
              v-if="isCurrentUserGroupOwner && member.userid !== currentUserid"
              content="Xóa thành viên"
              placement="left"
            >
              <button
                class="member-action-button danger"
                type="button"
                :aria-label="`Xóa ${member.fullname || member.userid} khỏi nhóm`"
                @click="removeMemberFromGroup(member)"
              >
                <Trash2 :size="15" />
              </button>
            </el-tooltip>
          </div>
        </div>
      </section>

      <section class="info-section">
        <div class="section-title">
          <h4>Ảnh / Video</h4>
        </div>
        <div v-if="sharedMedia.length" class="shared-media-grid">
          <a
            v-for="file in sharedMedia"
            :key="file.fileUrl"
            :href="file.fileUrl"
            target="_blank"
            rel="noopener noreferrer"
          >
            <img v-if="isImageAttachment(file)" :src="file.fileUrl" :alt="file.fileName" loading="lazy" />
            <span v-else>
              <FileVideo :size="22" />
            </span>
          </a>
        </div>
        <p v-else class="muted">Chưa có media</p>
      </section>

      <section class="info-section">
        <div class="section-title">
          <h4>File / Folder</h4>
        </div>
        <div v-if="sharedDocuments.length" class="shared-files">
          <a
            v-for="file in sharedDocuments"
            :key="file.fileUrl"
            :href="file.fileUrl"
            target="_blank"
            rel="noopener noreferrer"
          >
            <span class="shared-file-icon" :class="fileKind(file, 'file')">
              <component :is="fileIcon(file, 'file')" :size="16" />
              <small v-if="fileBadge(file, 'file')">{{ fileBadge(file, 'file') }}</small>
            </span>
            <span>{{ file.relativePath || file.fileName }}</span>
          </a>
        </div>
        <p v-else class="muted">Chưa có tệp</p>
      </section>

      <section class="info-section">
        <div class="section-title">
          <h4>Link</h4>
        </div>
        <div v-if="sharedLinks.length" class="shared-files">
          <a
            v-for="link in sharedLinks"
            :key="`${link.id}-${link.content}`"
            :href="safeLink(link.content)"
            target="_blank"
            rel="noopener noreferrer"
          >
            <span class="shared-file-icon link">
              <Link2 :size="16" />
            </span>
            <span>{{ link.content }}</span>
          </a>
        </div>
        <p v-else class="muted">Chưa có link</p>
      </section>
    </aside>

    <el-dialog v-model="profileDialogVisible" title="Cài đặt hồ sơ" width="460px" class="chat-dialog">
      <div class="profile-settings">
        <div class="avatar-editor">
          <el-avatar :size="84" :src="profileForm.avatar || undefined">
            {{ initials(profileForm.fullname || profileForm.userid) }}
          </el-avatar>
          <button class="avatar-upload-button" type="button" @click="avatarInputRef?.click()">
            <Camera :size="17" />
            Đổi ảnh
          </button>
          <input
            ref="avatarInputRef"
            hidden
            accept="image/*"
            type="file"
            @change="handleAvatarSelected"
          />
        </div>

        <div class="dialog-form">
          <label>Số thẻ</label>
          <input v-model="profileForm.userid" disabled type="text" />

          <label>Họ tên hiển thị</label>
          <input v-model.trim="profileForm.fullname" type="text" placeholder="Nhập họ tên" />
          <button class="dialog-button primary full-width" type="button" @click="saveProfile">
            Lưu hồ sơ
          </button>
        </div>

        <div class="dialog-form password-form">
          <label>Mật khẩu hiện tại</label>
          <input v-model="passwordForm.currentPassword" type="password" placeholder="Nhập mật khẩu hiện tại" />

          <label>Mật khẩu mới</label>
          <input v-model="passwordForm.newPassword" type="password" placeholder="Ít nhất 6 ký tự" />

          <label>Xác nhận mật khẩu mới</label>
          <input v-model="passwordForm.confirmPassword" type="password" placeholder="Nhập lại mật khẩu mới" />

          <button class="dialog-button primary full-width" type="button" @click="savePassword">
            Đổi mật khẩu
          </button>
        </div>
      </div>
    </el-dialog>

    <el-dialog v-model="contactDialogVisible" title="Thêm liên hệ" width="460px" class="chat-dialog">
      <div class="dialog-form">
        <label>Số thẻ</label>
        <div class="chip-input">
          <input
            v-model.trim="contactUserid"
            type="text"
            placeholder="Nhập số thẻ cần thêm"
            @keydown.enter.prevent="submitAddContact"
          />
          <button type="button" @click="submitAddContact">
            <UserPlus :size="16" />
          </button>
        </div>

        <div v-if="contactLookupLoading" class="list-state compact">Đang tìm...</div>
        <div v-else-if="contactLookupUsers.length" class="lookup-list">
          <div v-for="user in contactLookupUsers" :key="user.userid" class="user-result">
            <el-avatar :size="40" :src="user.avatar || undefined">
              {{ initials(user.fullname || user.userid) }}
            </el-avatar>
            <div class="user-result-main">
              <strong>{{ user.fullname || user.userid }}</strong>
              <span>{{ user.userid }}</span>
            </div>
            <button
              v-if="user.isContact"
              class="result-action ghost"
              type="button"
              @click="startDirectChat(user.userid)"
            >
              Nhắn tin
            </button>
            <button
              v-else
              class="result-action"
              type="button"
              @click="addContactFromUser(user)"
            >
              Thêm
            </button>
          </div>
        </div>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="contactDialogVisible = false">
          Hủy
        </button>
        <button class="dialog-button primary" type="button" @click="submitAddContact">
          Thêm liên hệ
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="groupDialogVisible" title="Tạo nhóm chat" width="480px" class="chat-dialog">
      <div class="dialog-form">
        <label>Tên nhóm</label>
        <input v-model.trim="groupName" type="text" placeholder="Ví dụ: Phòng IT" />

        <label>Thêm thành viên bằng số thẻ</label>
        <div class="chip-input">
          <input
            v-model.trim="groupMemberInput"
            type="text"
            placeholder="Nhập số thẻ"
            @keydown.enter.prevent="addGroupMemberChip"
          />
          <button type="button" @click="addGroupMemberChip">
            <Plus :size="16" />
          </button>
        </div>

        <div v-if="groupMemberUserids.length" class="chip-list">
          <span v-for="userid in groupMemberUserids" :key="userid" class="chip">
            {{ userid }}
            <button type="button" @click="removeGroupMemberChip(userid)">
              <X :size="13" />
            </button>
          </span>
        </div>

        <div v-if="contacts.length" class="contact-picker">
          <label>Chọn từ danh bạ</label>
          <div class="picker-list">
            <button
              v-for="contact in contacts"
              :key="contact.userid"
              :class="{ selected: groupMemberUserids.includes(contact.userid) }"
              type="button"
              @click="toggleGroupMember(contact.userid)"
            >
              <el-avatar :size="28" :src="contact.avatar || undefined">
                {{ initials(contact.fullname || contact.userid) }}
              </el-avatar>
              <span>{{ contact.fullname || contact.userid }}</span>
            </button>
          </div>
        </div>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="groupDialogVisible = false">
          Hủy
        </button>
        <button class="dialog-button primary" type="button" @click="createGroup">
          Tạo nhóm
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="addMemberDialogVisible" title="Thêm thành viên" width="420px" class="chat-dialog">
      <div class="dialog-form">
        <label>Số thẻ thành viên</label>
        <div class="chip-input">
          <input
            v-model.trim="addMemberInput"
            type="text"
            placeholder="Nhập số thẻ"
            @keydown.enter.prevent="addMemberChip"
          />
          <button type="button" @click="addMemberChip">
            <Plus :size="16" />
          </button>
        </div>

        <div v-if="addMemberUserids.length" class="chip-list">
          <span v-for="userid in addMemberUserids" :key="userid" class="chip">
            {{ userid }}
            <button type="button" @click="removeAddMemberChip(userid)">
              <X :size="13" />
            </button>
          </span>
        </div>

        <div v-if="contacts.length" class="contact-picker">
          <label>Chọn từ danh bạ</label>
          <div class="picker-list">
            <button
              v-for="contact in contacts"
              :key="contact.userid"
              :class="{ selected: addMemberUserids.includes(contact.userid) }"
              type="button"
              @click="toggleAddMember(contact.userid)"
            >
              <el-avatar :size="28" :src="contact.avatar || undefined">
                {{ initials(contact.fullname || contact.userid) }}
              </el-avatar>
              <span>{{ contact.fullname || contact.userid }}</span>
            </button>
          </div>
        </div>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="addMemberDialogVisible = false">
          Hủy
        </button>
        <button class="dialog-button primary" type="button" @click="submitAddMembers">
          Thêm
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="nicknameDialogVisible" title="Đặt biệt danh" width="420px" class="chat-dialog">
      <div class="dialog-form">
        <label>Thành viên</label>
        <input :value="nicknameTarget?.fullname || nicknameTarget?.userid || ''" disabled type="text" />

        <label>Biệt danh</label>
        <input
          v-model.trim="nicknameValue"
          type="text"
          maxlength="80"
          placeholder="Nhập biệt danh, để trống để xóa"
          @keydown.enter.prevent="submitNickname"
        />
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="nicknameDialogVisible = false">
          Hủy
        </button>
        <button class="dialog-button primary" type="button" @click="submitNickname">
          Lưu
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="forwardDialogVisible" title="Chuyển tiếp tin nhắn" width="440px" class="chat-dialog">
      <div class="forward-preview">
        <Forward :size="17" />
        <span>{{ forwardingMessage ? messageReferencePreview(forwardingMessage) : "" }}</span>
      </div>
      <div class="forward-conversation-list">
        <button
          v-for="conversation in conversations"
          :key="conversation.id"
          class="forward-conversation"
          :class="{ selected: forwardTargetConversationId === conversation.id }"
          type="button"
          @click="forwardTargetConversationId = conversation.id"
        >
          <el-avatar :size="34" :src="conversation.avatar || undefined">
            {{ initials(conversation.name) }}
          </el-avatar>
          <span>{{ conversation.name }}</span>
        </button>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="forwardDialogVisible = false">
          Hủy
        </button>
        <button class="dialog-button primary" type="button" @click="submitForward">
          Chuyển tiếp
        </button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { ElMessage, ElMessageBox } from "element-plus";
import dayjs from "dayjs";
import { Capacitor } from "@capacitor/core";
import { PushNotifications } from "@capacitor/push-notifications";
import {
  Camera,
  ChevronLeft,
  Download,
  File,
  FileArchive,
  FileAudio,
  FileCode,
  FileImage,
  FileSpreadsheet,
  FileText,
  FileVideo,
  Folder,
  FolderUp,
  Forward,
  Link2,
  LogOut,
  MessageCircle,
  Mic,
  Paperclip,
  Pencil,
  Plus,
  Presentation,
  Reply,
  Search,
  SendHorizontal,
  Square,
  Trash2,
  UploadCloud,
  UserPlus,
  Users,
  X,
} from "lucide-vue-next";
import chatApi from "@/store/chat";

const router = useRouter();
const enableNativePush = import.meta.env.VITE_ENABLE_PUSH === "true";
const currentUserid = localStorage.getItem("userid") || "";
const currentUser = ref({
  userid: currentUserid,
  fullname: localStorage.getItem("fullname") || "",
  avatar: localStorage.getItem("avatar") || "",
});

const conversations = ref([]);
const contacts = ref([]);
const messages = ref([]);
const panelMode = ref("chats");
const activeConversationId = ref(null);
const lastMessageIds = ref({});
const readState = ref({});
const unreadCounts = ref({});
const toastNotifications = ref([]);
const loadingConversations = ref(false);
const loadingContacts = ref(false);
const loadingMessages = ref(false);
const sending = ref(false);
const uploading = ref(false);
const isDragging = ref(false);
const dragDepth = ref(0);
const searchKeyword = ref("");
const searchedUsers = ref([]);
const searchingUsers = ref(false);
const composerText = ref("");
const mentionActive = ref(false);
const mentionQuery = ref("");
const mentionStartIndex = ref(-1);
const mentionSelectedIndex = ref(0);
const replyingTo = ref(null);
const forwardDialogVisible = ref(false);
const forwardingMessage = ref(null);
const forwardTargetConversationId = ref(null);
const pendingAttachments = ref([]);
const pendingAttachmentType = ref("file");
const isRecording = ref(false);
const preparingRecording = ref(false);
const recordingDuration = ref(0);
const groupDialogVisible = ref(false);
const groupName = ref("");
const groupMemberInput = ref("");
const groupMemberUserids = ref([]);
const membersExpanded = ref(false);
const addMemberDialogVisible = ref(false);
const addMemberInput = ref("");
const addMemberUserids = ref([]);
const nicknameDialogVisible = ref(false);
const nicknameTarget = ref(null);
const nicknameValue = ref("");
const contactDialogVisible = ref(false);
const contactUserid = ref("");
const contactLookupUsers = ref([]);
const contactLookupLoading = ref(false);
const profileDialogVisible = ref(false);
const profileForm = ref({ userid: currentUserid, fullname: "", avatar: "" });
const passwordForm = ref({ currentPassword: "", newPassword: "", confirmPassword: "" });
const messageListRef = ref(null);
const composerInputRef = ref(null);
const fileInputRef = ref(null);
const folderInputRef = ref(null);
const avatarInputRef = ref(null);
const groupAvatarInputRef = ref(null);
const groupBackgroundInputRef = ref(null);
let refreshTimer = null;
let searchTimer = null;
let contactLookupTimer = null;
let realtimeSocket = null;
let realtimeReconnectTimer = null;
let pushListenersRegistered = false;
let pushListenerHandles = [];
let searchRequestId = 0;
let contactLookupRequestId = 0;
let componentUnmounted = false;
let mediaRecorder = null;
let recordingStream = null;
let recordingChunks = [];
let recordingTimer = null;
let recordingStartedAt = 0;
let discardRecording = false;
const readStateStorageKey = `ys_chat_read_state_${currentUserid}`;
const unreadStorageKey = `ys_chat_unread_counts_${currentUserid}`;

const errorText = {
  CHAT_USER_NOT_FOUND: "Không tìm thấy số thẻ này.",
  CHAT_CONVERSATION_NOT_FOUND: "Không tìm thấy hội thoại.",
  CHAT_NO_PERMISSION: "Bạn không có quyền trong hội thoại này.",
  CHAT_EMPTY_MESSAGE: "Tin nhắn đang trống.",
  CHAT_INVALID_MESSAGE_TYPE: "Loại tin nhắn không hợp lệ.",
  CHAT_GROUP_NEEDS_MEMBER: "Nhóm cần ít nhất một thành viên khác.",
  CHAT_CANNOT_ADD_DIRECT_MEMBER: "Chat cá nhân không thể thêm thành viên. Vui lòng tạo nhóm mới.",
  CHAT_CANNOT_REMOVE_DIRECT_MEMBER: "Chat cá nhân không thể xóa thành viên.",
  CHAT_ONLY_OWNER_CAN_MANAGE_MEMBERS: "Chỉ chủ nhóm mới có thể xóa thành viên.",
  CHAT_MEMBER_NOT_FOUND: "Thành viên không còn trong nhóm.",
  INVALID_CREDENTIALS: "Mật khẩu hiện tại không đúng.",
  INVALID_INPUT: "Dữ liệu chưa hợp lệ.",
  UNAUTHORIZED: "Phiên đăng nhập đã hết hạn.",
  SYSTEM_ERROR: "Hệ thống đang lỗi, vui lòng thử lại.",
};

const activeConversation = computed(() =>
  conversations.value.find((conversation) => conversation.id === activeConversationId.value),
);

const panelTitle = computed(() => (panelMode.value === "contacts" ? "Danh bạ" : "Tin nhắn"));

const hasSearchKeyword = computed(() => searchKeyword.value.trim().length > 0);

const filteredConversations = computed(() => {
  const keyword = searchKeyword.value.trim().toLowerCase();
  if (!keyword) return conversations.value;
  return conversations.value.filter((conversation) => {
    const memberText = (conversation.members || [])
      .map((member) => `${member.fullname} ${member.nickname || ""} ${member.userid}`)
      .join(" ")
      .toLowerCase();
    return `${conversation.name} ${memberText}`.toLowerCase().includes(keyword);
  });
});

const messageListStyle = computed(() => {
  const background = activeConversation.value?.background;
  if (!background) return {};
  return {
    backgroundImage: `linear-gradient(rgba(248, 250, 252, 0.84), rgba(248, 250, 252, 0.84)), url("${cssUrl(background)}")`,
  };
});

const sharedAttachments = computed(() =>
  messages.value.flatMap((message) => message.attachments || []).reverse(),
);

const sharedMedia = computed(() =>
  sharedAttachments.value
    .filter((attachment) => isImageAttachment(attachment) || isVideoAttachment(attachment))
    .slice(0, 12),
);

const sharedDocuments = computed(() =>
  sharedAttachments.value
    .filter((attachment) => !isImageAttachment(attachment) && !isVideoAttachment(attachment) && !isAudioAttachment(attachment))
    .slice(0, 12),
);

const sharedLinks = computed(() =>
  messages.value
    .filter((message) => message.type === "link" && message.content)
    .slice()
    .reverse()
    .slice(0, 12),
);

const recordingDurationLabel = computed(() => formatDuration(recordingDuration.value));

const isCurrentUserGroupOwner = computed(() => {
  if (activeConversation.value?.type !== "group") return false;
  return (activeConversation.value.members || []).some(
    (member) => member.userid === currentUserid && member.role === "owner",
  );
});

const mentionSuggestions = computed(() => {
  if (!activeConversation.value || !mentionActive.value) return [];
  const keyword = mentionQuery.value.trim().toLowerCase();
  const members = activeConversation.value.members || [];
  return members
    .filter((member) => member.userid !== currentUserid)
    .filter((member) => {
      if (!keyword) return true;
      return `${member.fullname} ${member.nickname || ""} ${member.userid}`.toLowerCase().includes(keyword);
    })
    .slice(0, 6);
});

onMounted(async () => {
  readState.value = loadStoredObject(readStateStorageKey);
  unreadCounts.value = loadStoredObject(unreadStorageKey);
  await loadProfile();
  await loadContacts();
  await loadConversations(false);
  connectRealtime();
  await initPushNotifications();
  refreshTimer = window.setInterval(async () => {
    await loadConversations(false);
    if (activeConversationId.value) {
      await loadMessages(activeConversationId.value, false);
    }
  }, 5000);
});

onBeforeUnmount(() => {
  componentUnmounted = true;
  if (refreshTimer) window.clearInterval(refreshTimer);
  if (searchTimer) window.clearTimeout(searchTimer);
  if (contactLookupTimer) window.clearTimeout(contactLookupTimer);
  cancelVoiceRecording();
  disconnectRealtime();
  removePushListeners();
});

watch(searchKeyword, (value) => {
  if (searchTimer) window.clearTimeout(searchTimer);
  const keyword = value.trim();
  if (!keyword) {
    searchedUsers.value = [];
    searchingUsers.value = false;
    return;
  }

  searchingUsers.value = true;
  searchTimer = window.setTimeout(() => searchUsersRealtime(keyword), 250);
});

watch(contactUserid, (value) => {
  if (contactLookupTimer) window.clearTimeout(contactLookupTimer);
  const keyword = value.trim();
  if (!keyword) {
    contactLookupUsers.value = [];
    contactLookupLoading.value = false;
    return;
  }

  contactLookupLoading.value = true;
  contactLookupTimer = window.setTimeout(() => searchContactLookup(keyword), 250);
});

const loadStoredObject = (key) => {
  try {
    return JSON.parse(localStorage.getItem(key) || "{}");
  } catch {
    return {};
  }
};

const persistReadState = () => {
  localStorage.setItem(readStateStorageKey, JSON.stringify(readState.value));
};

const persistUnreadCounts = () => {
  localStorage.setItem(unreadStorageKey, JSON.stringify(unreadCounts.value));
};

const unreadCount = (conversationId) => Number(unreadCounts.value[conversationId] || 0);

const formatUnreadCount = (conversationId) => {
  const count = unreadCount(conversationId);
  if (count > 99) return "99+";
  return String(count);
};

const markConversationRead = (conversationId) => {
  const conversation = conversations.value.find((item) => item.id === conversationId);
  const lastMessageID = conversation?.lastMessage?.id || lastMessageIds.value[conversationId] || 0;
  unreadCounts.value = { ...unreadCounts.value, [conversationId]: 0 };
  readState.value = { ...readState.value, [conversationId]: lastMessageID };
  persistUnreadCounts();
  persistReadState();
};

const handleConversationNotifications = (nextConversations, isInitialLoad) => {
  const nextLastMessageIds = {};

  nextConversations.forEach((conversation) => {
    const lastMessage = conversation.lastMessage;
    if (!lastMessage?.id) return;

    const conversationId = conversation.id;
    const previousLastMessageId = lastMessageIds.value[conversationId];
    const lastReadMessageId = Number(readState.value[conversationId] || 0);
    const isNewMessage = previousLastMessageId && lastMessage.id !== previousLastMessageId;
    const isUnreadFromStorage = isInitialLoad && lastReadMessageId > 0 && lastMessage.id > lastReadMessageId;
    const fromOtherUser = lastMessage.senderUserid !== currentUserid;
    const isActiveConversation = conversationId === activeConversationId.value;

    if (fromOtherUser && (isNewMessage || isUnreadFromStorage)) {
      if (!isActiveConversation) {
        unreadCounts.value = {
          ...unreadCounts.value,
          [conversationId]: Math.max(1, unreadCount(conversationId) + (isNewMessage ? 1 : 0)),
        };
      }

      if (isNewMessage) {
        pushMessageNotification(conversation, lastMessage);
      }
    }

    nextLastMessageIds[conversationId] = lastMessage.id;
  });

  lastMessageIds.value = nextLastMessageIds;
  persistUnreadCounts();
};

const pushMessageNotification = (conversation, message) => {
  const id = `${conversation.id}-${message.id}-${Date.now()}`;
  const body = notificationPreview(message);
  toastNotifications.value = [
    {
      id,
      conversationId: conversation.id,
      title: conversation.name,
      avatar: conversation.avatar,
      body,
    },
    ...toastNotifications.value,
  ].slice(0, 4);

  window.setTimeout(() => dismissNotification(id), 6500);
};

const dismissNotification = (id) => {
  toastNotifications.value = toastNotifications.value.filter((item) => item.id !== id);
};

const openNotification = async (notification) => {
  dismissNotification(notification.id);
  const conversation = conversations.value.find((item) => item.id === notification.conversationId);
  if (conversation) {
    await selectConversation(conversation);
  }
};

const notificationPreview = (message) => {
  const sender = message.senderName ? `${message.senderName}: ` : "";
  if (message.type === "voice") return `${sender}Voice chat`;
  if (message.type === "file") return `${sender}Đã gửi tệp`;
  if (message.type === "folder") return `${sender}Đã gửi thư mục`;
  if (message.type === "link") return `${sender}Đã gửi liên kết`;
  return `${sender}${message.content || "Tin nhắn mới"}`;
};

const connectRealtime = () => {
  if (componentUnmounted || !localStorage.getItem("user_token") || realtimeSocket) return;

  try {
    realtimeSocket = new WebSocket(chatApi.getRealtimeUrl());
  } catch {
    scheduleRealtimeReconnect();
    return;
  }

  realtimeSocket.onmessage = (event) => {
    try {
      handleRealtimeEvent(JSON.parse(event.data));
    } catch {
      // Ignore malformed realtime frames; the periodic refresh remains the fallback.
    }
  };

  realtimeSocket.onclose = () => {
    realtimeSocket = null;
    scheduleRealtimeReconnect();
  };

  realtimeSocket.onerror = () => {
    realtimeSocket?.close();
  };
};

const scheduleRealtimeReconnect = () => {
  if (componentUnmounted || realtimeReconnectTimer) return;
  realtimeReconnectTimer = window.setTimeout(() => {
    realtimeReconnectTimer = null;
    connectRealtime();
  }, 2500);
};

const disconnectRealtime = () => {
  if (realtimeReconnectTimer) {
    window.clearTimeout(realtimeReconnectTimer);
    realtimeReconnectTimer = null;
  }
  if (realtimeSocket) {
    const socket = realtimeSocket;
    realtimeSocket = null;
    socket.onclose = null;
    socket.close();
  }
};

const handleRealtimeEvent = async (event) => {
  if (event?.type !== "chat.message.created" || !event.message?.id) return;

  const message = event.message;
  if (message.conversationId === activeConversationId.value) {
    const exists = messages.value.some((item) => item.id === message.id);
    if (!exists) {
      messages.value.push(message);
      await scrollToBottom();
    }
  }

  await loadConversations(false);
};

const initPushNotifications = async () => {
  if (!enableNativePush || !Capacitor.isNativePlatform() || pushListenersRegistered) return;

  try {
    const permission = await PushNotifications.requestPermissions();
    if (permission.receive !== "granted") return;

    pushListenersRegistered = true;
    const registrationHandle = await PushNotifications.addListener("registration", async (token) => {
      try {
        await chatApi.registerDeviceToken(token.value, Capacitor.getPlatform());
      } catch (error) {
        showApiError(error);
      }
    });
    pushListenerHandles.push(registrationHandle);

    const actionHandle = await PushNotifications.addListener("pushNotificationActionPerformed", async (action) => {
      const conversationId = Number(action.notification?.data?.conversationId || 0);
      if (!conversationId) return;
      await openConversationById(conversationId);
    });
    pushListenerHandles.push(actionHandle);

    await PushNotifications.register();
  } catch {
    // Push setup can fail on emulators without Play Services; chat still works through realtime/polling.
  }
};

const removePushListeners = () => {
  pushListenerHandles.forEach((handle) => {
    void handle.remove();
  });
  pushListenerHandles = [];
  pushListenersRegistered = false;
};

const openConversationById = async (conversationId) => {
  let conversation = conversations.value.find((item) => item.id === conversationId);
  if (!conversation) {
    await loadConversations(false);
    conversation = conversations.value.find((item) => item.id === conversationId);
  }
  if (conversation) {
    await selectConversation(conversation);
  }
};

const setPanelMode = (mode) => {
  panelMode.value = mode;
  if (mode === "contacts") {
    loadContacts();
  }
};

const isContactUser = (userid) => contacts.value.some((contact) => contact.userid === userid);

const withContactState = (user) => ({
  ...user,
  isContact: Boolean(user.isContact) || isContactUser(user.userid),
});

const sortUsers = (users) =>
  [...users].sort((first, second) =>
    (first.fullname || first.userid || "").localeCompare(second.fullname || second.userid || "", "vi"),
  );

const loadContacts = async () => {
  try {
    loadingContacts.value = true;
    const res = await chatApi.getContacts();
    contacts.value = sortUsers((res.data?.contacts || []).map((contact) => ({ ...contact, isContact: true })));
    searchedUsers.value = searchedUsers.value.map(withContactState);
    contactLookupUsers.value = contactLookupUsers.value.map(withContactState);
  } catch (error) {
    showApiError(error);
  } finally {
    loadingContacts.value = false;
  }
};

const searchUsersRealtime = async (keyword) => {
  const requestId = ++searchRequestId;
  try {
    const res = await chatApi.searchUsers(keyword);
    if (requestId !== searchRequestId || keyword !== searchKeyword.value.trim()) return;
    searchedUsers.value = (res.data?.users || []).map(withContactState);
  } catch (error) {
    if (requestId === searchRequestId) showApiError(error);
  } finally {
    if (requestId === searchRequestId) searchingUsers.value = false;
  }
};

const searchContactLookup = async (keyword) => {
  const requestId = ++contactLookupRequestId;
  try {
    const res = await chatApi.searchUsers(keyword);
    if (requestId !== contactLookupRequestId || keyword !== contactUserid.value.trim()) return;
    contactLookupUsers.value = (res.data?.users || []).map(withContactState).slice(0, 5);
  } catch (error) {
    if (requestId === contactLookupRequestId) showApiError(error);
  } finally {
    if (requestId === contactLookupRequestId) contactLookupLoading.value = false;
  }
};

const openContactDialog = () => {
  contactDialogVisible.value = true;
  contactUserid.value = "";
  contactLookupUsers.value = [];
};

const upsertContact = (contact) => {
  if (!contact?.userid) return;
  const nextContact = { ...contact, isContact: true };
  const withoutCurrent = contacts.value.filter((item) => item.userid !== nextContact.userid);
  contacts.value = sortUsers([...withoutCurrent, nextContact]);
  searchedUsers.value = searchedUsers.value.map((user) =>
    user.userid === nextContact.userid ? { ...user, isContact: true } : user,
  );
  contactLookupUsers.value = contactLookupUsers.value.map((user) =>
    user.userid === nextContact.userid ? { ...user, isContact: true } : user,
  );
};

const addContactByUserid = async (userid) => {
  const contactUseridValue = String(userid || "").trim();
  if (!contactUseridValue) {
    ElMessage.warning("Vui lòng nhập số thẻ.");
    return null;
  }
  if (contactUseridValue === currentUserid) {
    ElMessage.warning("Không thể tự thêm chính mình vào danh bạ.");
    return null;
  }

  const res = await chatApi.addContact(contactUseridValue);
  const contact = res.data?.contact;
  upsertContact(contact);
  ElMessage.success("Đã thêm liên hệ.");
  return contact;
};

const addContactFromUser = async (user) => {
  try {
    await addContactByUserid(user.userid);
  } catch (error) {
    showApiError(error);
  }
};

const submitAddContact = async () => {
  try {
    const contact = await addContactByUserid(contactUserid.value);
    if (!contact) return;
    contactDialogVisible.value = false;
    contactUserid.value = "";
    panelMode.value = "contacts";
  } catch (error) {
    showApiError(error);
  }
};

const loadProfile = async () => {
  try {
    const res = await chatApi.getProfile();
    applyProfile(res.data?.user);
  } catch (error) {
    showApiError(error);
  }
};

const applyProfile = (user) => {
  if (!user) return;
  currentUser.value = {
    userid: user.userid,
    fullname: user.fullname || user.userid,
    avatar: user.avatar || "",
  };
  profileForm.value = { ...currentUser.value };
  localStorage.setItem("userid", currentUser.value.userid);
  localStorage.setItem("fullname", currentUser.value.fullname);
  localStorage.setItem("avatar", currentUser.value.avatar);
};

const openProfileDialog = async () => {
  profileDialogVisible.value = true;
  profileForm.value = { ...currentUser.value };
  passwordForm.value = { currentPassword: "", newPassword: "", confirmPassword: "" };
  await loadProfile();
};

const saveProfile = async () => {
  if (!profileForm.value.fullname.trim()) {
    ElMessage.warning("Vui lòng nhập họ tên hiển thị.");
    return;
  }

  try {
    const res = await chatApi.updateProfile(profileForm.value.fullname.trim());
    applyProfile(res.data?.user);
    await loadConversations(false);
    ElMessage.success("Đã cập nhật hồ sơ.");
  } catch (error) {
    showApiError(error);
  }
};

const savePassword = async () => {
  if (!passwordForm.value.currentPassword || !passwordForm.value.newPassword) {
    ElMessage.warning("Vui lòng nhập đầy đủ mật khẩu.");
    return;
  }
  if (passwordForm.value.newPassword.length < 6) {
    ElMessage.warning("Mật khẩu mới phải có ít nhất 6 ký tự.");
    return;
  }
  if (passwordForm.value.newPassword !== passwordForm.value.confirmPassword) {
    ElMessage.warning("Mật khẩu xác nhận không khớp.");
    return;
  }

  try {
    await chatApi.changePassword(passwordForm.value.currentPassword, passwordForm.value.newPassword);
    passwordForm.value = { currentPassword: "", newPassword: "", confirmPassword: "" };
    ElMessage.success("Đã đổi mật khẩu.");
  } catch (error) {
    showApiError(error);
  }
};

const handleAvatarSelected = async (event) => {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (!file) return;

  try {
    const res = await chatApi.uploadAvatar(file);
    applyProfile(res.data?.user);
    await loadConversations(false);
    ElMessage.success("Đã cập nhật ảnh đại diện.");
  } catch (error) {
    showApiError(error);
  }
};

const handleGroupImageSelected = async (event, field) => {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (!file || !activeConversationId.value || activeConversation.value?.type !== "group") return;

  try {
    const uploadRes = await chatApi.uploadFiles([{ file, relativePath: file.name }]);
    const attachment = uploadRes.data?.attachments?.[0];
    if (!attachment?.fileUrl) {
      ElMessage.error("Không tải được ảnh.");
      return;
    }

    const payload = {
      avatar: activeConversation.value.avatar || "",
      background: activeConversation.value.background || "",
      [field]: attachment.fileUrl,
    };
    const res = await chatApi.updateConversationSettings(activeConversationId.value, payload);
    await loadConversations(false);
    if (res.data?.conversation) {
      await selectConversation(res.data.conversation);
    }
    ElMessage.success(field === "avatar" ? "Đã cập nhật ảnh đại diện nhóm." : "Đã cập nhật ảnh nền hội thoại.");
  } catch (error) {
    showApiError(error);
  }
};

const loadConversations = async (selectFirst = false) => {
  try {
    loadingConversations.value = true;
    const res = await chatApi.getConversations();
    const nextConversations = res.data?.conversations || [];
    const isInitialLoad = Object.keys(lastMessageIds.value).length === 0;
    handleConversationNotifications(nextConversations, isInitialLoad);
    conversations.value = nextConversations;

    const activeStillExists = conversations.value.some(
      (conversation) => conversation.id === activeConversationId.value,
    );
    if (!activeStillExists) {
      activeConversationId.value = null;
      messages.value = [];
    }
    if (selectFirst && !activeConversationId.value && conversations.value.length) {
      await selectConversation(conversations.value[0]);
    } else if (activeConversationId.value) {
      markConversationRead(activeConversationId.value);
    }
  } catch (error) {
    showApiError(error);
  } finally {
    loadingConversations.value = false;
  }
};

const selectConversation = async (conversation) => {
  activeConversationId.value = conversation.id;
  membersExpanded.value = false;
  cancelReply();
  await loadMessages(conversation.id, true);
  markConversationRead(conversation.id);
};

const loadMessages = async (conversationId, shouldScroll = true) => {
  try {
    loadingMessages.value = shouldScroll;
    const res = await chatApi.getMessages(conversationId);
    if (conversationId !== activeConversationId.value) return;
    messages.value = res.data?.messages || [];
    if (conversationId === activeConversationId.value) {
      markConversationRead(conversationId);
    }
    if (shouldScroll) await scrollToBottom();
  } catch (error) {
    showApiError(error);
  } finally {
    loadingMessages.value = false;
  }
};

const startDirectChat = async (userid) => {
  const targetUserid = String(userid || "").trim();
  if (!targetUserid) {
    ElMessage.warning("Nhập số thẻ cần chat.");
    return;
  }
  if (targetUserid === currentUserid) {
    ElMessage.warning("Không thể tự chat với chính mình.");
    return;
  }

  try {
    const res = await chatApi.createDirectConversation(targetUserid);
    const conversation = res.data?.conversation;
    panelMode.value = "chats";
    searchKeyword.value = "";
    contactDialogVisible.value = false;
    await loadConversations(false);
    if (conversation) await selectConversation(conversation);
  } catch (error) {
    showApiError(error);
  }
};

const openGroupDialog = async () => {
  groupDialogVisible.value = true;
  groupName.value = "";
  groupMemberInput.value = "";
  groupMemberUserids.value = [];
  await loadContacts();
};

const addGroupMemberChip = () => {
  const userid = groupMemberInput.value.trim();
  if (!userid) return;
  if (!groupMemberUserids.value.includes(userid) && userid !== currentUserid) {
    groupMemberUserids.value.push(userid);
  }
  groupMemberInput.value = "";
};

const removeGroupMemberChip = (userid) => {
  groupMemberUserids.value = groupMemberUserids.value.filter((item) => item !== userid);
};

const toggleGroupMember = (userid) => {
  if (!userid || userid === currentUserid) return;
  if (groupMemberUserids.value.includes(userid)) {
    removeGroupMemberChip(userid);
    return;
  }
  groupMemberUserids.value.push(userid);
};

const createGroup = async () => {
  addGroupMemberChip();
  if (!groupName.value) {
    ElMessage.warning("Nhập tên nhóm.");
    return;
  }

  try {
    const res = await chatApi.createGroupConversation(groupName.value, groupMemberUserids.value);
    groupDialogVisible.value = false;
    await loadConversations(false);
    if (res.data?.conversation) await selectConversation(res.data.conversation);
  } catch (error) {
    showApiError(error);
  }
};

const openAddMemberDialog = async () => {
  if (!activeConversationId.value) return;
  if (activeConversation.value?.type !== "group") {
    ElMessage.warning("Chỉ nhóm chat mới có thể thêm thành viên.");
    return;
  }
  addMemberDialogVisible.value = true;
  addMemberInput.value = "";
  addMemberUserids.value = [];
  await loadContacts();
};

const addMemberChip = () => {
  const userid = addMemberInput.value.trim();
  if (!userid) return;
  const currentMemberUserids = activeConversation.value?.members?.map((member) => member.userid) || [];
  if (!addMemberUserids.value.includes(userid) && !currentMemberUserids.includes(userid)) {
    addMemberUserids.value.push(userid);
  }
  addMemberInput.value = "";
};

const removeAddMemberChip = (userid) => {
  addMemberUserids.value = addMemberUserids.value.filter((item) => item !== userid);
};

const toggleAddMember = (userid) => {
  if (!userid || userid === currentUserid) return;
  const currentMemberUserids = activeConversation.value?.members?.map((member) => member.userid) || [];
  if (currentMemberUserids.includes(userid)) return;
  if (addMemberUserids.value.includes(userid)) {
    removeAddMemberChip(userid);
    return;
  }
  addMemberUserids.value.push(userid);
};

const submitAddMembers = async () => {
  addMemberChip();
  if (!activeConversationId.value || addMemberUserids.value.length === 0) {
    ElMessage.warning("Nhập số thẻ thành viên.");
    return;
  }

  try {
    await chatApi.addConversationMembers(activeConversationId.value, addMemberUserids.value);
    addMemberDialogVisible.value = false;
    await loadConversations(false);
  } catch (error) {
    showApiError(error);
  }
};

const removeMemberFromGroup = async (member) => {
  if (!activeConversationId.value || !member?.userid) return;
  if (!isCurrentUserGroupOwner.value) {
    ElMessage.warning("Chỉ chủ nhóm mới có thể xóa thành viên.");
    return;
  }
  if (member.userid === currentUserid) return;

  const memberName = member.fullname || member.userid;
  try {
    await ElMessageBox.confirm(
      `Xóa ${memberName} khỏi nhóm này?`,
      "Xóa thành viên",
      {
        confirmButtonText: "Xóa",
        cancelButtonText: "Hủy",
        type: "warning",
      },
    );
  } catch {
    return;
  }

  try {
    await chatApi.removeConversationMember(activeConversationId.value, member.userid);
    await loadConversations(false);
    ElMessage.success("Đã xóa thành viên.");
  } catch (error) {
    showApiError(error);
  }
};

const openNicknameDialog = (member) => {
  if (!activeConversationId.value || !member?.userid) return;
  nicknameTarget.value = member;
  nicknameValue.value = member.nickname || "";
  nicknameDialogVisible.value = true;
};

const submitNickname = async () => {
  if (!activeConversationId.value || !nicknameTarget.value?.userid) return;

  try {
    await chatApi.updateConversationMemberNickname(
      activeConversationId.value,
      nicknameTarget.value.userid,
      nicknameValue.value,
    );
    nicknameDialogVisible.value = false;
    const conversationId = activeConversationId.value;
    await loadConversations(false);
    if (conversationId) {
      await loadMessages(conversationId, false);
    }
    ElMessage.success(nicknameValue.value ? "Đã lưu biệt danh." : "Đã xóa biệt danh.");
  } catch (error) {
    showApiError(error);
  }
};

const updateMentionState = () => {
  if (!activeConversation.value) {
    closeMentionMenu();
    return;
  }

  const input = composerInputRef.value;
  const cursor = input?.selectionStart ?? composerText.value.length;
  const textBeforeCursor = composerText.value.slice(0, cursor);
  const atIndex = textBeforeCursor.lastIndexOf("@");

  if (atIndex < 0) {
    closeMentionMenu();
    return;
  }

  const charBeforeAt = atIndex === 0 ? " " : textBeforeCursor[atIndex - 1];
  const query = textBeforeCursor.slice(atIndex + 1);
  if (!/\s/.test(charBeforeAt) || query.includes("\n") || query.includes("@")) {
    closeMentionMenu();
    return;
  }

  const queryChanged = mentionQuery.value !== query;
  mentionStartIndex.value = atIndex;
  mentionQuery.value = query;
  mentionActive.value = true;
  mentionSelectedIndex.value = queryChanged
    ? 0
    : Math.min(mentionSelectedIndex.value, Math.max(mentionSuggestions.value.length - 1, 0));
};

const closeMentionMenu = () => {
  mentionActive.value = false;
  mentionQuery.value = "";
  mentionStartIndex.value = -1;
  mentionSelectedIndex.value = 0;
};

const moveMentionSelection = (direction) => {
  if (!mentionActive.value || !mentionSuggestions.value.length) return;
  const total = mentionSuggestions.value.length;
  mentionSelectedIndex.value = (mentionSelectedIndex.value + direction + total) % total;
};

const handleMentionArrow = (event, direction) => {
  if (!mentionActive.value || !mentionSuggestions.value.length) return;
  event.preventDefault();
  moveMentionSelection(direction);
};

const handleMentionTab = (event) => {
  if (!mentionActive.value || !mentionSuggestions.value.length) return;
  event.preventDefault();
  applySelectedMention();
};

const applySelectedMention = () => {
  if (!mentionActive.value || !mentionSuggestions.value.length) return false;
  insertMention(mentionSuggestions.value[mentionSelectedIndex.value] || mentionSuggestions.value[0]);
  return true;
};

const handleComposerEnter = () => {
  if (applySelectedMention()) return;
  sendCurrentMessage();
};

const insertMention = async (member) => {
  const input = composerInputRef.value;
  const cursor = input?.selectionStart ?? composerText.value.length;
  const start = mentionStartIndex.value >= 0 ? mentionStartIndex.value : cursor;
  const mentionText = `@${displayName(member) || member.userid} `;
  composerText.value = `${composerText.value.slice(0, start)}${mentionText}${composerText.value.slice(cursor)}`;
  closeMentionMenu();

  await nextTick();
  const nextCursor = start + mentionText.length;
  composerInputRef.value?.focus();
  composerInputRef.value?.setSelectionRange(nextCursor, nextCursor);
};

const handleFilesSelected = async (event, type) => {
  const files = Array.from(event.target.files || []);
  event.target.value = "";
  await prepareAndUploadFiles(files.map((file) => ({ file, relativePath: file.webkitRelativePath || file.name })), type);
};

const prepareAndUploadFiles = async (fileItems, type) => {
  if (!fileItems.length) return;

  try {
    uploading.value = true;
    const res = await chatApi.uploadFiles(fileItems);
    pendingAttachments.value = [
      ...pendingAttachments.value,
      ...(res.data?.attachments || []),
    ];
    pendingAttachmentType.value = type;

    if (type === "folder" && !composerText.value) {
      composerText.value = folderNameFromPath(fileItems[0].relativePath) || "Thư mục";
    }
    ElMessage.success(`Đã tải ${fileItems.length} tệp lên.`);
  } catch (error) {
    showApiError(error);
  } finally {
    uploading.value = false;
  }
};

const toggleVoiceRecording = () => {
  if (isRecording.value) {
    stopVoiceRecording();
    return;
  }
  startVoiceRecording();
};

const startVoiceRecording = async () => {
  if (!activeConversationId.value) {
    ElMessage.warning("Vui long chon hoi thoai truoc khi ghi voice.");
    return;
  }
  if (preparingRecording.value || isRecording.value || sending.value || uploading.value) return;
  if (pendingAttachments.value.length) {
    ElMessage.warning("Vui long gui hoac xoa tep dang cho truoc khi ghi voice.");
    return;
  }
  if (!window.navigator?.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
    ElMessage.error("Trinh duyet nay chua ho tro ghi am.");
    return;
  }

  try {
    preparingRecording.value = true;
    const stream = await window.navigator.mediaDevices.getUserMedia({ audio: true });
    recordingStream = stream;
    if (componentUnmounted) {
      releaseRecordingStream();
      return;
    }
    const mimeType = supportedAudioMimeType();
    const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);

    mediaRecorder = recorder;
    recordingChunks = [];
    discardRecording = false;

    recorder.ondataavailable = (event) => {
      if (event.data?.size) {
        recordingChunks.push(event.data);
      }
    };
    recorder.onerror = () => {
      ElMessage.error("Khong the ghi am.");
      cancelVoiceRecording();
    };
    recorder.onstop = () => finalizeVoiceRecording(recorder.mimeType || mimeType);

    recorder.start();
    isRecording.value = true;
    recordingDuration.value = 0;
    recordingStartedAt = Date.now();
    recordingTimer = window.setInterval(updateRecordingDuration, 250);
  } catch {
    releaseRecordingStream();
    ElMessage.error("Khong the truy cap micro.");
  } finally {
    preparingRecording.value = false;
  }
};

const stopVoiceRecording = () => {
  if (!mediaRecorder || mediaRecorder.state === "inactive") return;
  mediaRecorder.stop();
};

const cancelVoiceRecording = () => {
  discardRecording = true;
  if (mediaRecorder && mediaRecorder.state !== "inactive") {
    mediaRecorder.stop();
    return;
  }
  resetRecordingState();
};

const finalizeVoiceRecording = async (mimeType) => {
  const chunks = [...recordingChunks];
  const shouldDiscard = discardRecording;
  resetRecordingState();

  if (shouldDiscard) return;
  if (!chunks.length) {
    ElMessage.warning("Voice dang trong.");
    return;
  }

  const blobType = mimeType || chunks[0]?.type || "audio/webm";
  const blob = new Blob(chunks, { type: blobType });
  if (!blob.size) {
    ElMessage.warning("Voice dang trong.");
    return;
  }

  const file = new File([blob], `voice-${dayjs().format("YYYYMMDD-HHmmss")}.${audioExtension(blob.type)}`, {
    type: blob.type || "audio/webm",
  });
  await sendVoiceMessage(file);
};

const sendVoiceMessage = async (file) => {
  if (!activeConversationId.value) return;

  try {
    uploading.value = true;
    const uploadRes = await chatApi.uploadFiles([{ file, relativePath: file.name }]);
    const attachments = uploadRes.data?.attachments || [];
    if (!attachments.length) {
      ElMessage.error("Khong the tai voice len.");
      return;
    }

    sending.value = true;
    const messageRes = await chatApi.sendMessage(activeConversationId.value, {
      type: "voice",
      content: "",
      attachments,
    });
    if (messageRes.data?.message) {
      messages.value.push(messageRes.data.message);
    }
    await loadConversations(false);
    await scrollToBottom();
  } catch (error) {
    showApiError(error);
  } finally {
    uploading.value = false;
    sending.value = false;
  }
};

const supportedAudioMimeType = () => {
  if (typeof MediaRecorder === "undefined" || typeof MediaRecorder.isTypeSupported !== "function") {
    return "";
  }
  return [
    "audio/webm;codecs=opus",
    "audio/webm",
    "audio/ogg;codecs=opus",
    "audio/mp4",
  ].find((type) => MediaRecorder.isTypeSupported(type)) || "";
};

const audioExtension = (mimeType = "") => {
  const normalized = mimeType.toLowerCase();
  if (normalized.includes("mp4")) return "m4a";
  if (normalized.includes("ogg")) return "ogg";
  if (normalized.includes("wav")) return "wav";
  return "webm";
};

const updateRecordingDuration = () => {
  if (!recordingStartedAt) return;
  recordingDuration.value = Math.max(0, Math.floor((Date.now() - recordingStartedAt) / 1000));
};

const resetRecordingState = () => {
  if (recordingTimer) {
    window.clearInterval(recordingTimer);
    recordingTimer = null;
  }
  releaseRecordingStream();
  mediaRecorder = null;
  recordingChunks = [];
  recordingStartedAt = 0;
  discardRecording = false;
  isRecording.value = false;
  recordingDuration.value = 0;
};

const releaseRecordingStream = () => {
  recordingStream?.getTracks().forEach((track) => track.stop());
  recordingStream = null;
};

const onDragEnter = (event) => {
  if (!hasFiles(event)) return;
  dragDepth.value += 1;
  isDragging.value = true;
};

const onDragOver = (event) => {
  if (!hasFiles(event)) return;
  event.dataTransfer.dropEffect = activeConversationId.value ? "copy" : "none";
  isDragging.value = true;
};

const onDragLeave = () => {
  dragDepth.value = Math.max(0, dragDepth.value - 1);
  if (dragDepth.value === 0) {
    isDragging.value = false;
  }
};

const handleDrop = async (event) => {
  dragDepth.value = 0;
  isDragging.value = false;

  if (!activeConversationId.value) {
    ElMessage.warning("Chọn hội thoại trước khi gửi tệp.");
    return;
  }

  const fileItems = await filesFromDrop(event.dataTransfer);
  const hasFolder = fileItems.some((item) => item.relativePath.includes("/"));
  await prepareAndUploadFiles(fileItems, hasFolder ? "folder" : "file");
};

const filesFromDrop = async (dataTransfer) => {
  const items = Array.from(dataTransfer?.items || []);
  const entries = items
    .map((item) => (typeof item.webkitGetAsEntry === "function" ? item.webkitGetAsEntry() : null))
    .filter(Boolean);

  if (entries.length) {
    const nested = await Promise.all(entries.map((entry) => readEntry(entry, "")));
    return nested.flat();
  }

  return Array.from(dataTransfer?.files || []).map((file) => ({
    file,
    relativePath: file.webkitRelativePath || file.name,
  }));
};

const readEntry = (entry, parentPath) => {
  if (entry.isFile) {
    return new Promise((resolve, reject) => {
      entry.file(
        (file) => resolve([{ file, relativePath: `${parentPath}${file.name}` }]),
        reject,
      );
    });
  }

  if (!entry.isDirectory) return Promise.resolve([]);

  const directoryPath = `${parentPath}${entry.name}/`;
  const reader = entry.createReader();
  const batches = [];

  return new Promise((resolve, reject) => {
    const readBatch = () => {
      reader.readEntries(async (entries) => {
        if (!entries.length) {
          try {
            const nested = await Promise.all(batches.map((child) => readEntry(child, directoryPath)));
            resolve(nested.flat());
          } catch (error) {
            reject(error);
          }
          return;
        }
        batches.push(...entries);
        readBatch();
      }, reject);
    };

    readBatch();
  });
};

const hasFiles = (event) => Array.from(event.dataTransfer?.types || []).includes("Files");

const removePendingAttachment = (fileUrl) => {
  pendingAttachments.value = pendingAttachments.value.filter(
    (attachment) => attachment.fileUrl !== fileUrl,
  );
};

const startReply = (message) => {
  replyingTo.value = toMessageReference(message);
  nextTick(() => composerInputRef.value?.focus());
};

const cancelReply = () => {
  replyingTo.value = null;
};

const openForwardDialog = (message) => {
  forwardingMessage.value = message;
  forwardTargetConversationId.value = conversations.value.find((conversation) => conversation.id !== activeConversationId.value)?.id
    || activeConversationId.value;
  forwardDialogVisible.value = true;
};

const submitForward = async () => {
  if (!forwardingMessage.value || !forwardTargetConversationId.value || sending.value) return;

  const message = forwardingMessage.value;
  try {
    sending.value = true;
    const res = await chatApi.sendMessage(forwardTargetConversationId.value, {
      type: message.type,
      content: message.content || "",
      forwardedFromMessageId: message.id,
      attachments: cloneAttachments(message.attachments || []),
    });
    forwardDialogVisible.value = false;
    forwardingMessage.value = null;
    if (forwardTargetConversationId.value === activeConversationId.value && res.data?.message) {
      messages.value.push(res.data.message);
      await scrollToBottom();
    }
    await loadConversations(false);
    ElMessage.success("Đã chuyển tiếp tin nhắn.");
  } catch (error) {
    showApiError(error);
  } finally {
    sending.value = false;
  }
};

const sendCurrentMessage = async () => {
  if (!activeConversationId.value || sending.value || uploading.value || isRecording.value) return;

  const content = composerText.value.trim();
  const hasAttachments = pendingAttachments.value.length > 0;
  const type = !hasAttachments && isLinkMessageContent(content) ? "link" : hasAttachments ? pendingAttachmentType.value : "text";

  if (!content && !hasAttachments) {
    ElMessage.warning("Tin nhắn đang trống.");
    return;
  }

  try {
    sending.value = true;
    const res = await chatApi.sendMessage(activeConversationId.value, {
      type,
      content,
      replyToMessageId: replyingTo.value?.id || 0,
      attachments: pendingAttachments.value,
    });
    if (res.data?.message) {
      messages.value.push(res.data.message);
    }
    composerText.value = "";
    cancelReply();
    pendingAttachments.value = [];
    await loadConversations(false);
    await scrollToBottom();
  } catch (error) {
    showApiError(error);
  } finally {
    sending.value = false;
  }
};

const scrollToBottom = async () => {
  await nextTick();
  const el = messageListRef.value;
  if (!el) return;

  const scroll = () => {
    el.scrollTop = el.scrollHeight;
  };

  scroll();
  window.requestAnimationFrame(scroll);
  window.setTimeout(scroll, 120);
};

const scrollToMessage = async (messageId) => {
  await nextTick();
  const target = document.getElementById(`message-${messageId}`);
  if (!target) return;
  target.scrollIntoView({ behavior: "smooth", block: "center" });
  target.classList.add("highlight");
  window.setTimeout(() => target.classList.remove("highlight"), 1400);
};

const handleLogout = () => {
  disconnectRealtime();
  removePushListeners();
  localStorage.removeItem("user_token");
  localStorage.removeItem("userid");
  localStorage.removeItem("fullname");
  localStorage.removeItem("account_id");
  router.push("/login");
};

const isOwnMessage = (message) => message.senderUserid === currentUserid;

const toMessageReference = (message = {}) => ({
  id: message.id,
  senderUserid: message.senderUserid,
  senderName: message.senderName,
  type: message.type,
  content: message.content || "",
});

const cloneAttachments = (attachments = []) =>
  attachments.map((attachment) => ({
    fileName: attachment.fileName,
    fileUrl: attachment.fileUrl,
    fileSize: attachment.fileSize,
    mimeType: attachment.mimeType,
    relativePath: attachment.relativePath,
  }));

const messageReferencePreview = (message = {}) => {
  if (message.content) return message.content;
  if (message.type === "voice") return "Voice chat";
  if (message.type === "folder") return "Thư mục đính kèm";
  if (message.type === "file") return "Tệp đính kèm";
  if (message.type === "link") return "Liên kết";
  return "Tin nhắn";
};

const messageTextParts = (content = "") => {
  const labels = mentionLabels();
  if (!content || !labels.length) return [{ text: content, isMention: false }];

  const parts = [];
  const lowerContent = content.toLowerCase();
  let cursor = 0;

  while (cursor < content.length) {
    let nextMatch = null;
    for (const label of labels) {
      const index = lowerContent.indexOf(label.lower, cursor);
      if (index < 0) continue;
      if (!nextMatch || index < nextMatch.index || (index === nextMatch.index && label.text.length > nextMatch.text.length)) {
        nextMatch = { ...label, index };
      }
    }

    if (!nextMatch) {
      parts.push({ text: content.slice(cursor), isMention: false });
      break;
    }

    if (nextMatch.index > cursor) {
      parts.push({ text: content.slice(cursor, nextMatch.index), isMention: false });
    }
    parts.push({
      text: content.slice(nextMatch.index, nextMatch.index + nextMatch.text.length),
      isMention: true,
    });
    cursor = nextMatch.index + nextMatch.text.length;
  }

  return parts;
};

const mentionLabels = () => {
  const members = activeConversation.value?.members || [];
  const labels = [];
  const seen = new Set();

  members.forEach((member) => {
    [`@${displayName(member)}`, `@${member.fullname}`, `@${member.userid}`].forEach((label) => {
      const normalized = label.trim();
      if (normalized.length <= 1 || seen.has(normalized.toLowerCase())) return;
      seen.add(normalized.toLowerCase());
      labels.push({ text: normalized, lower: normalized.toLowerCase() });
    });
  });

  return labels.sort((first, second) => second.text.length - first.text.length);
};

const imageAttachments = (message) =>
  (message.attachments || []).filter((attachment) => isImageAttachment(attachment));

const voiceAttachments = (message) =>
  message.type === "voice"
    ? (message.attachments || []).filter((attachment) => isAudioAttachment(attachment))
    : [];

const fileAttachments = (message) =>
  (message.attachments || []).filter(
    (attachment) => !isImageAttachment(attachment) && !(message.type === "voice" && isAudioAttachment(attachment)),
  );

const isImageAttachment = (attachment) => {
  const mimeType = (attachment.mimeType || "").toLowerCase();
  return mimeType.startsWith("image/") || ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"].includes(fileExt(attachment));
};

const isAudioAttachment = (attachment) => {
  const mimeType = (attachment.mimeType || "").toLowerCase();
  if (mimeType.startsWith("video/")) return false;
  return mimeType.startsWith("audio/") || ["mp3", "wav", "m4a", "aac", "flac", "ogg", "oga", "webm"].includes(fileExt(attachment));
};

const isVideoAttachment = (attachment) => {
  const mimeType = (attachment.mimeType || "").toLowerCase();
  return mimeType.startsWith("video/") || ["mp4", "mov", "avi", "mkv", "webm"].includes(fileExt(attachment));
};

const fileExt = (attachment) => {
  const name = (attachment.fileName || attachment.relativePath || "").toLowerCase();
  const ext = name.split(".").pop();
  return ext && ext !== name ? ext : "";
};

const fileKind = (attachment, messageType = "file") => {
  if (messageType === "voice") return "voice";
  if (messageType === "folder") return "folder";
  if (isImageAttachment(attachment)) return "image";
  if (isAudioAttachment(attachment)) return "audio";
  const ext = fileExt(attachment);
  if (["doc", "docx"].includes(ext)) return "word";
  if (["xls", "xlsx", "csv"].includes(ext)) return "excel";
  if (["ppt", "pptx"].includes(ext)) return "ppt";
  if (["zip", "rar", "7z", "tar", "gz"].includes(ext)) return "archive";
  if (["mp4", "mov", "avi", "mkv", "webm"].includes(ext)) return "video";
  if (["js", "ts", "go", "json", "html", "css", "vue", "xml", "sql"].includes(ext)) return "code";
  if (ext === "pdf") return "pdf";
  return "file";
};

const fileKindLabel = (attachment, messageType = "file") => {
  const kind = fileKind(attachment, messageType);
  const labels = {
    archive: "Tệp nén",
    audio: "Âm thanh",
    code: "Mã nguồn",
    excel: "Excel",
    file: fileExt(attachment).toUpperCase() || "Tệp",
    folder: "Thư mục",
    image: "Hình ảnh",
    pdf: "PDF",
    ppt: "PowerPoint",
    video: "Video",
    voice: "Voice chat",
    word: "Word",
  };
  return labels[kind] || "Tệp";
};

const fileBadge = (attachment, messageType = "file") => {
  const kind = fileKind(attachment, messageType);
  if (kind === "folder") return "";
  if (kind === "voice") return "VOC";
  if (kind === "audio") return "AUD";
  if (kind === "video") return "VID";
  if (kind === "image") return "IMG";
  if (kind === "archive") return "ZIP";
  if (kind === "word") return "DOC";
  if (kind === "excel") return "XLS";
  if (kind === "ppt") return "PPT";
  if (kind === "code") return "CODE";
  if (kind === "pdf") return "PDF";
  return fileExt(attachment).slice(0, 4).toUpperCase();
};

const fileIcon = (attachment, messageType = "file") => {
  const kind = fileKind(attachment, messageType);
  const icons = {
    archive: FileArchive,
    audio: FileAudio,
    code: FileCode,
    excel: FileSpreadsheet,
    file: File,
    folder: Folder,
    image: FileImage,
    pdf: FileText,
    ppt: Presentation,
    video: FileVideo,
    voice: FileAudio,
    word: FileText,
  };
  return icons[kind] || FileText;
};

const folderNameFromPath = (path = "") => path.split("/").filter(Boolean)[0] || "";

const displayName = (user = {}) => user.nickname || user.fullname || user.userid || "";

const initials = (name = "") => {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (!words.length) return "YS";
  return words
    .slice(-2)
    .map((word) => word[0])
    .join("")
    .toUpperCase();
};

const lastMessagePreview = (conversation) => {
  const message = conversation.lastMessage;
  if (!message) return "Chưa có tin nhắn";
  const prefix = message.senderUserid === currentUserid ? "Bạn: " : "";
  if (message.type === "voice") return `${prefix}Voice chat`;
  if (message.type === "file") return `${prefix}Tệp đính kèm`;
  if (message.type === "folder") return `${prefix}Thư mục đính kèm`;
  if (message.type === "link") return `${prefix}Liên kết`;
  return `${prefix}${message.content || ""}`;
};

const conversationTime = (conversation) => {
  const time = conversation.lastMessage?.createdAt || conversation.updatedAt;
  if (!time) return "";
  const value = dayjs(time);
  return value.isSame(dayjs(), "day") ? value.format("HH:mm") : value.format("DD/MM");
};

const formatTime = (time) => (time ? dayjs(time).format("HH:mm") : "");

const formatDuration = (seconds = 0) => {
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(remainingSeconds).padStart(2, "0")}`;
};

const formatBytes = (bytes = 0) => {
  if (!bytes) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / 1024 ** index).toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
};

const downloadFileName = (attachment = {}) => attachment.fileName || attachment.relativePath?.split("/").pop() || "";

const safeLink = (value) => {
  if (/^https?:\/\//i.test(value)) return value;
  return `https://${value}`;
};

const isLinkMessageContent = (value = "") => {
  const content = value.trim();
  if (!content || /\s/.test(content)) return false;
  return /^(https?:\/\/)?([\w-]+\.)+[\w-]{2,}(\/\S*)?$/i.test(content);
};

const cssUrl = (value = "") => value.replace(/["\\]/g, "\\$&");

const showApiError = (error) => {
  const code = error?.response?.data?.error;
  if (code === "UNAUTHORIZED") {
    handleLogout();
    return;
  }
  ElMessage.error(errorText[code] || code || "Có lỗi xảy ra.");
};
</script>

<style scoped>
.chat-shell {
  --brand: #0891b2;
  --brand-dark: #0e7490;
  --brand-focus: #22d3ee;
  --brand-soft: #cffafe;
  --brand-softest: #ecfeff;
  --brand-border: #a5f3fc;
  --brand-tint: rgba(8, 145, 178, 0.12);
  --brand-overlay: rgba(236, 254, 255, 0.92);
  width: 100vw;
  height: 100vh;
  display: grid;
  grid-template-columns: 72px minmax(300px, 360px) minmax(0, 1fr) minmax(260px, 318px);
  overflow: hidden;
  background: #eef2f7;
  color: #172033;
  position: relative;
}

button,
input,
textarea {
  font: inherit;
}

button {
  border: 0;
}

a {
  text-decoration: none;
}

.drop-overlay {
  position: fixed;
  inset: 12px;
  z-index: 10000;
  display: grid;
  align-content: center;
  justify-items: center;
  gap: 8px;
  border: 2px dashed var(--brand);
  border-radius: 8px;
  background: var(--brand-overlay);
  color: var(--brand-dark);
  pointer-events: none;
}

.drop-overlay span {
  color: #506176;
}

.notification-stack {
  position: fixed;
  right: 18px;
  bottom: 18px;
  z-index: 12000;
  display: grid;
  gap: 10px;
  width: min(360px, calc(100vw - 28px));
}

.message-toast {
  min-width: 0;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: 10px;
  align-items: center;
  padding: 10px;
  border-radius: 8px;
  background: #ffffff;
  color: #172033;
  box-shadow: 0 18px 50px rgba(15, 23, 42, 0.22);
  border: 1px solid #dbe7f6;
  cursor: pointer;
  text-align: left;
}

.message-toast span {
  min-width: 0;
  display: grid;
  gap: 1px;
}

.message-toast strong,
.message-toast small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.message-toast small {
  color: #64748b;
}

.app-rail {
  background: var(--brand);
  color: #ffffff;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 14px 10px;
}

.rail-logo {
  width: 44px;
  height: 44px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: #ffffff;
}

.rail-logo img {
  width: 34px;
  height: 34px;
  object-fit: contain;
}

.rail-actions,
.rail-bottom {
  display: grid;
  gap: 10px;
}

.rail-actions {
  margin-top: 32px;
}

.rail-bottom {
  margin-top: auto;
}

.rail-button,
.icon-button,
.tool-button,
.send-button,
.download-button {
  display: inline-grid;
  place-items: center;
  cursor: pointer;
  transition: background-color 0.18s ease, color 0.18s ease, transform 0.18s ease;
}

.rail-button {
  width: 46px;
  height: 46px;
  border-radius: 8px;
  background: transparent;
  color: #ffffff;
}

.rail-button:hover,
.rail-button.active {
  background: rgba(255, 255, 255, 0.18);
}

.profile-rail-button {
  background: rgba(255, 255, 255, 0.14);
}

.conversation-panel,
.info-panel,
.chat-header,
.composer {
  background: #ffffff;
}

.conversation-panel {
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  border-right: 1px solid #dce3ee;
}

.panel-header {
  height: 88px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 18px 18px 12px;
  flex: 0 0 auto;
}

.eyebrow {
  margin: 0 0 2px;
  color: var(--brand);
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0;
}

.panel-header h1,
.chat-title h2,
.empty-chat h2,
.profile-block h3,
.section-title h4 {
  margin: 0;
}

.panel-header h1 {
  font-size: 24px;
  line-height: 1.2;
}

.panel-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.icon-button {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  background: #f0f4fa;
  color: #243044;
}

.icon-button.primary {
  background: var(--brand);
  color: #ffffff;
}

.icon-button:hover,
.tool-button:hover {
  background: var(--brand-soft);
  color: var(--brand-dark);
}

.search-box,
.quick-start,
.chip-input {
  display: flex;
  align-items: center;
  gap: 8px;
  border-radius: 8px;
  background: #f2f5f9;
  border: 1px solid transparent;
}

.search-box {
  margin: 0 18px 10px;
  padding: 0 12px;
  height: 42px;
  color: #6b778c;
  flex: 0 0 auto;
}

.search-box input,
.quick-start input,
.chip-input input,
.dialog-form input {
  min-width: 0;
  width: 100%;
  border: 0;
  outline: 0;
  background: transparent;
  color: #172033;
}

.quick-start {
  margin: 0 18px 12px;
  height: 42px;
  padding-left: 12px;
  flex: 0 0 auto;
}

.quick-start button,
.chip-input button {
  width: 36px;
  height: 36px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand);
  color: #ffffff;
  cursor: pointer;
  flex: 0 0 auto;
}

.conversation-list {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  padding: 4px 8px 12px;
}

.search-results {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  padding: 4px 8px 12px;
}

.result-section {
  display: grid;
  gap: 4px;
  margin-bottom: 14px;
}

.result-title {
  padding: 8px 10px 4px;
  color: #687789;
  font-size: 12px;
  font-weight: 800;
  text-transform: uppercase;
}

.conversation-item {
  width: 100%;
  min-height: 68px;
  display: flex;
  gap: 12px;
  align-items: center;
  padding: 10px;
  border-radius: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
  text-align: left;
}

.conversation-item:hover {
  background: var(--brand-softest);
}

.conversation-item.active {
  background: var(--brand-soft);
}

.conversation-item.has-unread .conversation-name {
  color: #0f172a;
  font-weight: 800;
}

.conversation-item.has-unread .conversation-main p {
  color: #1e293b;
  font-weight: 700;
}

.conversation-avatar {
  flex: 0 0 auto;
}

.conversation-avatar.group {
  width: 44px;
  height: 44px;
  position: relative;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: linear-gradient(135deg, var(--brand-focus), var(--brand));
  color: #ffffff;
  box-shadow: inset 0 0 0 2px rgba(255, 255, 255, 0.28);
}

.conversation-avatar.group span {
  position: absolute;
  right: -3px;
  bottom: -3px;
  min-width: 18px;
  height: 18px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: #ffffff;
  border: 1px solid var(--brand-border);
  color: var(--brand-dark);
  font-size: 11px;
  font-weight: 800;
}

.conversation-main {
  min-width: 0;
  flex: 1;
}

.conversation-top {
  display: flex;
  gap: 8px;
  justify-content: space-between;
  align-items: baseline;
}

.conversation-meta {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  gap: 6px;
}

.unread-badge {
  min-width: 20px;
  height: 20px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: #ff3b30;
  color: #ffffff;
  font-size: 11px;
  font-weight: 800;
  padding: 0 6px;
}

.conversation-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 700;
}

.conversation-top time {
  flex: 0 0 auto;
  color: #8a95a7;
  font-size: 12px;
}

.conversation-main p {
  margin: 3px 0 0;
  color: #6b778c;
  font-size: 13px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-result {
  min-height: 62px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 10px;
  border-radius: 8px;
  background: transparent;
}

.user-result:hover {
  background: var(--brand-softest);
}

.user-result-main {
  min-width: 0;
  flex: 1;
  display: grid;
  gap: 2px;
}

.user-result-main strong,
.user-result-main span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-result-main span {
  color: #6b778c;
  font-size: 13px;
}

.result-action {
  flex: 0 0 auto;
  height: 32px;
  border-radius: 8px;
  padding: 0 10px;
  background: var(--brand);
  color: #ffffff;
  cursor: pointer;
  font-weight: 800;
}

.result-action.ghost {
  background: var(--brand-soft);
  color: var(--brand-dark);
}

.list-state,
.empty-list,
.message-state,
.empty-chat {
  color: #7b8798;
}

.list-state,
.empty-list {
  padding: 28px 18px;
  text-align: center;
}

.list-state.compact {
  padding: 10px 0;
}

.empty-list {
  display: grid;
  justify-items: center;
  gap: 8px;
}

.chat-pane {
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: #f4f7fb;
  overflow: hidden;
}

.chat-shell:not(.has-active) .chat-pane {
  grid-column: 3 / -1;
}

.chat-header {
  height: 72px;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 18px;
  border-bottom: 1px solid #dce3ee;
  flex: 0 0 auto;
}

.mobile-back {
  display: none;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  background: #f0f4fa;
  color: #243044;
}

.chat-title {
  min-width: 0;
  flex: 1;
}

.chat-title h2 {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 18px;
  line-height: 1.3;
}

.chat-title span,
.profile-block span,
.member-item span,
.attachment-meta span,
.muted {
  color: #7b8798;
  font-size: 13px;
}

.chat-actions {
  display: flex;
  gap: 8px;
}

.message-list {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 20px 28px;
  background-position: center;
  background-size: cover;
}

.message-state,
.empty-chat {
  height: 100%;
  display: grid;
  align-content: center;
  justify-items: center;
  gap: 10px;
  text-align: center;
}

.empty-chat > svg,
.empty-chat > h2,
.empty-chat > p {
  display: none;
}

.welcome-copy {
  display: grid;
  justify-items: center;
  gap: 10px;
  max-width: 420px;
}

.welcome-logo {
  width: 86px;
  height: 86px;
  object-fit: contain;
  margin-bottom: 4px;
}

.welcome-copy h2 {
  margin: 0;
  color: #18243a;
  font-size: 24px;
  line-height: 1.25;
}

.welcome-copy p {
  margin: 0;
  color: #7b8798;
  font-size: 15px;
}

.empty-chat p {
  margin: 0;
}

.message-row {
  display: flex;
  gap: 8px;
  margin: 0 0 12px;
  align-items: flex-end;
}

.message-row.highlight .message-bubble {
  box-shadow: 0 0 0 3px var(--brand-tint), 0 1px 1px rgba(15, 23, 42, 0.04);
}

.message-row.own {
  justify-content: flex-end;
}

.message-stack {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  max-width: min(620px, 74%);
}

.message-row.own .message-stack {
  align-items: flex-end;
}

.sender-name {
  margin: 0 0 4px 2px;
  color: #637083;
  font-size: 12px;
  font-weight: 600;
}

.message-bubble {
  min-width: 84px;
  max-width: 100%;
  padding: 9px 10px 7px;
  border-radius: 8px;
  background: #ffffff;
  border: 1px solid #e2e8f0;
  box-shadow: 0 1px 1px rgba(15, 23, 42, 0.04);
  overflow-wrap: anywhere;
}

.message-row.own .message-bubble {
  background: var(--brand-soft);
  border-color: var(--brand-border);
}

.reply-reference {
  width: 100%;
  display: grid;
  gap: 2px;
  margin-bottom: 7px;
  padding: 7px 8px;
  border-left: 3px solid var(--brand);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.72);
  color: #243044;
  cursor: pointer;
  text-align: left;
}

.reply-reference strong,
.reply-compose strong {
  font-size: 12px;
  color: var(--brand-dark);
}

.reply-reference span,
.reply-compose span,
.forward-preview span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #637083;
  font-size: 12px;
}

.forwarded-label {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-bottom: 6px;
  color: #64748b;
  font-size: 12px;
  font-weight: 700;
}

.message-actions {
  display: flex;
  gap: 4px;
  margin-top: 4px;
  opacity: 0.62;
  transition: opacity 0.15s ease;
}

.message-stack:hover .message-actions {
  opacity: 1;
}

.message-actions button {
  width: 28px;
  height: 28px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: #ffffff;
  color: #64748b;
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.08);
  cursor: pointer;
}

.message-actions button:hover {
  color: var(--brand-dark);
  background: var(--brand-softest);
}

.message-text {
  margin: 0;
  white-space: pre-wrap;
}

.message-text .mention {
  color: var(--brand-dark);
  font-weight: 800;
  background: var(--brand-tint);
  border-radius: 6px;
  padding: 1px 3px;
}

.message-link {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--brand-dark);
  word-break: break-all;
}

.message-bubble time {
  display: block;
  margin-top: 4px;
  color: #7b8798;
  font-size: 11px;
  text-align: right;
}

.image-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 168px));
  gap: 6px;
  margin-top: 4px;
}

.image-grid a {
  display: block;
  border-radius: 8px;
  overflow: hidden;
  background: #dce3ee;
  border: 1px solid rgba(0, 0, 0, 0.05);
}

.image-grid img {
  width: 100%;
  height: 150px;
  display: block;
  object-fit: cover;
}

.voice-list {
  display: grid;
  gap: 8px;
  margin-top: 6px;
}

.voice-player {
  min-width: min(360px, 58vw);
  display: grid;
  grid-template-columns: 36px minmax(0, 1fr) 30px;
  gap: 8px;
  align-items: center;
  padding: 8px;
  border-radius: 8px;
  background: rgba(240, 237, 255, 0.7);
  border: 1px solid #d9d0ff;
}

.voice-icon {
  width: 36px;
  height: 36px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: #f0edff;
  color: #6d4aff;
}

.voice-player audio {
  width: 100%;
  min-width: 0;
  height: 34px;
}

.attachment-list {
  display: grid;
  gap: 8px;
  margin-top: 6px;
}

.attachment-item {
  min-width: min(390px, 58vw);
  display: grid;
  grid-template-columns: 38px minmax(0, 1fr) 30px;
  gap: 8px;
  align-items: center;
  padding: 8px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.74);
  border: 1px solid #dce7f7;
}

.attachment-icon {
  width: 38px;
  height: 38px;
  position: relative;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand);
}

.attachment-badge,
.shared-file-icon small {
  position: absolute;
  right: -5px;
  bottom: -5px;
  min-width: 23px;
  height: 14px;
  display: grid;
  place-items: center;
  border-radius: 4px;
  background: #ffffff;
  border: 1px solid currentColor;
  color: inherit;
  font-size: 8px;
  font-weight: 900;
  line-height: 1;
  padding: 0 3px;
}

.attachment-item.word .attachment-icon {
  background: var(--brand-softest);
  color: var(--brand);
}

.attachment-item.excel .attachment-icon {
  background: #e7f7ed;
  color: #16803d;
}

.attachment-item.ppt .attachment-icon {
  background: #fff0e8;
  color: #d45a16;
}

.attachment-item.pdf .attachment-icon {
  background: #ffecec;
  color: #dc2626;
}

.attachment-item.archive .attachment-icon,
.attachment-item.folder .attachment-icon {
  background: #fff7dd;
  color: #b77900;
}

.attachment-item.audio .attachment-icon,
.attachment-item.voice .attachment-icon,
.attachment-item.video .attachment-icon,
.attachment-item.code .attachment-icon {
  background: #f0edff;
  color: #6d4aff;
}

.attachment-meta {
  min-width: 0;
  display: grid;
  gap: 1px;
}

.attachment-meta a,
.shared-files a {
  color: #172033;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.download-button {
  width: 30px;
  height: 30px;
  border-radius: 8px;
  color: var(--brand-dark);
}

.composer {
  border-top: 1px solid #dce3ee;
  padding: 10px 14px 12px;
  flex: 0 0 auto;
}

.reply-compose,
.forward-preview {
  min-width: 0;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
  padding: 8px 10px;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand-dark);
}

.reply-compose > div {
  min-width: 0;
  display: grid;
}

.reply-compose button {
  width: 28px;
  height: 28px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.forward-preview {
  grid-template-columns: auto minmax(0, 1fr);
}

.forward-conversation-list {
  display: grid;
  gap: 8px;
  max-height: 360px;
  overflow-y: auto;
}

.forward-conversation {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
  padding: 8px;
  border-radius: 8px;
  background: #f5f7fb;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.forward-conversation.selected {
  background: var(--brand-soft);
  box-shadow: inset 0 0 0 1px var(--brand-focus);
}

.forward-conversation span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pending-files {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding-bottom: 8px;
}

.pending-file,
.chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  max-width: 300px;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand-dark);
  padding: 6px 8px;
  font-size: 13px;
}

.pending-file span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pending-file small {
  flex: 0 0 auto;
  color: #5d7190;
}

.pending-file button,
.chip button,
.section-title button {
  display: grid;
  place-items: center;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.voice-recording {
  height: 40px;
  display: grid;
  grid-template-columns: auto auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 9px;
  padding: 0 10px;
  margin-bottom: 8px;
  border-radius: 8px;
  background: #fff1f2;
  border: 1px solid #fecdd3;
  color: #b91c1c;
}

.voice-recording span:last-of-type {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #7f1d1d;
}

.voice-recording button {
  width: 30px;
  height: 30px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.record-dot {
  width: 9px;
  height: 9px;
  border-radius: 999px;
  background: #ef4444;
  box-shadow: 0 0 0 4px rgba(239, 68, 68, 0.14);
}

.composer-body {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: 8px;
  align-items: end;
}

.composer-input-wrap {
  position: relative;
  min-width: 0;
}

.mention-menu {
  position: absolute;
  left: 0;
  right: 0;
  bottom: calc(100% + 8px);
  z-index: 30;
  max-height: 240px;
  overflow-y: auto;
  display: grid;
  gap: 2px;
  padding: 6px;
  border-radius: 8px;
  border: 1px solid #d8e4f4;
  background: #ffffff;
  box-shadow: 0 16px 42px rgba(15, 23, 42, 0.18);
}

.mention-menu button {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 8px;
  border-radius: 8px;
  padding: 7px;
  background: transparent;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.mention-menu button:hover,
.mention-menu button.selected {
  background: var(--brand-softest);
}

.mention-menu span {
  min-width: 0;
  display: grid;
}

.mention-menu strong,
.mention-menu small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mention-menu small {
  color: #64748b;
}

.composer-tools {
  display: flex;
  gap: 4px;
  padding-bottom: 1px;
}

.tool-button {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  background: transparent;
  color: #596779;
}

.tool-button.active {
  background: var(--brand-soft);
  color: var(--brand);
}

.tool-button.recording {
  background: #fee2e2;
  color: #dc2626;
}

.tool-button:disabled {
  cursor: not-allowed;
  opacity: 0.52;
}

textarea {
  width: 100%;
  min-height: 38px;
  max-height: 120px;
  resize: none;
  border: 1px solid #dce3ee;
  border-radius: 8px;
  outline: 0;
  padding: 8px 11px;
  color: #172033;
  line-height: 1.4;
}

textarea:focus,
.search-box:focus-within,
.quick-start:focus-within,
.chip-input:focus-within,
.dialog-form input:focus {
  border-color: var(--brand-focus);
  box-shadow: 0 0 0 3px var(--brand-tint);
}

.send-button {
  width: 40px;
  height: 38px;
  border-radius: 8px;
  background: var(--brand);
  color: #ffffff;
}

.send-button:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}

.info-panel {
  min-width: 0;
  min-height: 0;
  overflow-y: auto;
  border-left: 1px solid #dce3ee;
  padding: 20px 16px;
}

.profile-block {
  display: grid;
  justify-items: center;
  gap: 8px;
  padding-bottom: 18px;
  border-bottom: 1px solid #edf1f6;
  text-align: center;
}

.conversation-cover {
  width: 100%;
  aspect-ratio: 16 / 7;
  position: relative;
  overflow: hidden;
  border-radius: 8px;
  background: linear-gradient(135deg, var(--brand-softest), #f5f7fb);
}

.conversation-cover img {
  width: 100%;
  height: 100%;
  display: block;
  object-fit: cover;
}

.conversation-cover.empty {
  border: 1px dashed var(--brand-border);
}

.conversation-avatar-editor {
  position: relative;
}

.conversation-avatar-editor.with-cover {
  margin-top: -34px;
}

.cover-upload-button,
.avatar-upload-button.mini {
  width: 30px;
  height: 30px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.92);
  color: var(--brand-dark);
  box-shadow: 0 8px 18px rgba(15, 23, 42, 0.12);
  cursor: pointer;
}

.cover-upload-button {
  position: absolute;
  right: 8px;
  bottom: 8px;
}

.avatar-upload-button.mini {
  position: absolute;
  right: -4px;
  bottom: 0;
  padding: 0;
}

.profile-block h3 {
  font-size: 18px;
  line-height: 1.3;
}

.info-section {
  padding: 18px 0 0;
}

.section-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
}

.section-title h4 {
  font-size: 14px;
  text-transform: uppercase;
  color: #596779;
  letter-spacing: 0;
}

.member-list,
.shared-files {
  display: grid;
  gap: 8px;
}

.member-count-button {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 0;
  background: transparent;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.member-count-button svg {
  color: var(--brand-dark);
}

.member-item {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.member-meta {
  min-width: 0;
  flex: 1;
  display: grid;
}

.member-item strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.member-action-button {
  width: 30px;
  height: 30px;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand-dark);
  cursor: pointer;
}

.member-action-button:hover {
  background: var(--brand-soft);
}

.member-action-button.danger {
  background: #fff1f2;
  color: #e11d48;
}

.member-action-button.danger:hover {
  background: #ffe4e6;
}

.shared-files a {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  padding: 8px;
  border-radius: 8px;
  background: #f5f7fb;
}

.shared-files a > span:last-child {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.shared-media-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 6px;
}

.shared-media-grid a {
  aspect-ratio: 1;
  display: grid;
  place-items: center;
  overflow: hidden;
  border-radius: 8px;
  background: #f5f7fb;
  color: var(--brand);
}

.shared-media-grid img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.shared-file-icon {
  width: 28px;
  height: 28px;
  position: relative;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand);
}

.shared-file-icon.excel {
  background: #e7f7ed;
  color: #16803d;
}

.shared-file-icon.ppt {
  background: #fff0e8;
  color: #d45a16;
}

.shared-file-icon.pdf {
  background: #ffecec;
  color: #dc2626;
}

.shared-file-icon.archive,
.shared-file-icon.folder {
  background: #fff7dd;
  color: #b77900;
}

.shared-file-icon.audio,
.shared-file-icon.voice,
.shared-file-icon.video,
.shared-file-icon.code {
  background: #f0edff;
  color: #6d4aff;
}

.shared-file-icon.link {
  background: var(--brand-softest);
  color: var(--brand-dark);
}

.dialog-form {
  display: grid;
  gap: 10px;
}

.profile-settings {
  display: grid;
  gap: 18px;
}

.avatar-editor {
  display: grid;
  justify-items: center;
  gap: 10px;
  padding-bottom: 4px;
}

.avatar-upload-button {
  height: 34px;
  display: inline-flex;
  align-items: center;
  gap: 7px;
  border-radius: 8px;
  padding: 0 12px;
  background: var(--brand-soft);
  color: var(--brand-dark);
  cursor: pointer;
  font-weight: 700;
}

.password-form {
  padding-top: 16px;
  border-top: 1px solid #edf1f6;
}

.full-width {
  width: 100%;
}

.dialog-form label {
  color: #334155;
  font-weight: 700;
}

.dialog-form > input {
  height: 40px;
  border: 1px solid #dce3ee;
  border-radius: 8px;
  padding: 0 10px;
}

.chip-input {
  height: 42px;
  padding-left: 10px;
}

.chip-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.lookup-list {
  display: grid;
  gap: 4px;
  border-top: 1px solid #edf1f6;
  padding-top: 8px;
}

.contact-picker {
  display: grid;
  gap: 8px;
  padding-top: 8px;
  border-top: 1px solid #edf1f6;
}

.picker-list {
  max-height: 180px;
  min-height: 0;
  overflow-y: auto;
  display: grid;
  gap: 6px;
}

.picker-list button {
  min-height: 40px;
  display: flex;
  align-items: center;
  gap: 9px;
  border-radius: 8px;
  padding: 6px 8px;
  background: #f5f7fb;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.picker-list button.selected {
  background: var(--brand-soft);
  color: var(--brand-dark);
  box-shadow: inset 0 0 0 1px var(--brand-focus);
}

.picker-list span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dialog-button {
  min-width: 82px;
  height: 36px;
  border-radius: 8px;
  padding: 0 14px;
  cursor: pointer;
  font-weight: 700;
}

.dialog-button.ghost {
  background: #edf2f7;
  color: #243044;
}

.dialog-button.primary {
  background: var(--brand);
  color: #ffffff;
}

:deep(.el-dialog) {
  border-radius: 8px;
}

:deep(.el-avatar) {
  flex: 0 0 auto;
  background: var(--brand-soft);
  color: var(--brand-dark);
  font-weight: 800;
}

::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: transparent;
}

::-webkit-scrollbar-thumb {
  background: #c4cfdd;
  border-radius: 8px;
}

@media (max-width: 1180px) {
  .chat-shell {
    grid-template-columns: 72px minmax(280px, 340px) minmax(0, 1fr);
  }

  .info-panel {
    display: none;
  }
}

@media (max-width: 820px) {
  .chat-shell {
    grid-template-columns: 1fr;
  }

  .app-rail,
  .info-panel {
    display: none;
  }

  .conversation-panel,
  .chat-pane {
    grid-column: 1;
    grid-row: 1;
    height: 100vh;
  }

  .chat-pane {
    display: none;
  }

  .chat-shell.has-active .conversation-panel {
    display: none;
  }

  .chat-shell.has-active .chat-pane {
    display: flex;
  }

  .mobile-back {
    display: grid;
    place-items: center;
  }

  .message-list {
    padding: 16px 12px;
  }

  .message-stack {
    max-width: 84%;
  }

  .attachment-item {
    min-width: min(330px, 82vw);
  }

  .voice-player {
    min-width: min(320px, 82vw);
  }

  .image-grid {
    grid-template-columns: repeat(2, minmax(0, 136px));
  }

  .image-grid img {
    height: 122px;
  }

  .composer-body {
    grid-template-columns: minmax(0, 1fr) auto;
  }

  .composer-tools {
    grid-column: 1 / -1;
  }
}
</style>
