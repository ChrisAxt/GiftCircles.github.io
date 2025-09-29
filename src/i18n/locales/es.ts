// src/i18n/es.ts
const es = {
  translation: {
    languages: {
      nativeNames: { es: 'Español' },
    },

    titles: {
      event: 'Detalles del event',
      createEvent: 'Crear event',
      joinEvent: 'Unirse al event',
      editEvent: 'Editar event',
      list: 'Listas',
      addItem: 'Añadir artículo',
      createList: 'Crear lista',
    },

    profile: {
      title: 'Perfil',
      email: 'Correo',
      displayName: 'Nombre visible',
      saveName: 'Guardar nombre',
      memberSince: 'Miembro desde',
      stats: { events: 'Eventos', listsCreated: 'Listas creadas' },
      account: 'Cuenta',
      signOut: 'Cerrar sesión',
      dangerTitle: 'Zona de riesgo',
      dangerDesc: 'Esto eliminará tu perfil de forma permanente y te quitará de los eventos.',
      delete: 'Eliminar cuenta',
      alerts: {
        nameRequiredTitle: 'Nombre requerido',
        nameRequiredBody: 'Introduce un nombre visible.',
        saveOkTitle: 'Guardado',
        saveOkBody: 'Se actualizó tu nombre visible.',
        saveErrTitle: 'Error al guardar',
        signOutErrTitle: 'Error al cerrar sesión',
        deleteConfirmTitle: '¿Eliminar tu cuenta?',
        deleteConfirmBody: 'Esto borrará tu perfil, tus membresías y te cerrará la sesión.',
        cancel: 'Cancelar',
        confirmDelete: 'Eliminar',
        deleteErrTitle: 'Error al eliminar',
        deleteOkTitle: 'Cuenta eliminada',
        deleteOkBody: 'Tu cuenta ha sido eliminada.',
      },
      settings: { title: 'Ajustes', appearance: 'Apariencia', language: 'Idioma', push: 'Notificaciones push' },
      common: { system: 'Sistema', light: 'Claro', dark: 'Oscuro', english: 'Inglés', swedish: 'Sueco' },
    },

    navigation: {
      tabs: {
        events: 'Eventos',
        lists: 'Listas',
        claimed: 'Reservados',
        profile: 'Perfil',
      },
    },

    eventList: {
      header: {
        welcome: '¡Bienvenido de nuevo,',
        tagline: 'Coordina regalos fácilmente',
        emptyName: 'tú',
      },
      stats: {
        activeEvents: 'Eventos activos',
        itemsClaimed: 'Artículos reservados',
        toPurchase: 'Por comprar',
      },
      title: 'Tus eventos',
      toolbar: { create: 'Crear', join: 'Unirse' },

      empty: {
        title: 'Aún no hay eventos.',
        body: 'Crea tu primer event o únete con un código.',
        create: 'Crear event',
        join: 'Unirse con código',
      },

      eventCard: {
        members_one: '{{count}} miembro',
        members_other: '{{count}} miembros',
        claimedShort: '{{claimed}}/{{total}} reservados',
        today: 'hoy',
        tomorrow: 'mañana',
        inDays_one: 'en {{count}} día',
        inDays_other: 'en {{count}} días',
        daysAgo_one: 'hace {{count}} día',
        daysAgo_other: 'hace {{count}} días',
        noDate: 'Sin fecha',
      },

      actions: { share: 'Compartir', edit: 'Editar', delete: 'Eliminar', leave: 'Salir' },

      alerts: {
        deleteTitle: '¿Eliminar el event?',
        deleteBody: 'Esto eliminará todas las listas, artículos y reservas para todos.',
        leaveTitle: '¿Salir del event?',
        leaveBody: 'Se te quitará del event y se limpiarán tus reservas.',
        cancel: 'Cancelar',
        confirmDelete: 'Eliminar',
        confirmLeave: 'Salir',
      },

      errors: {
        loadFailed: 'No se pudieron cargar los eventos',
        generic: 'Ocurrió un problema',
      },
    },

    eventDetail: {
      header: {
        adminNote: 'Eres admin de este event.',
        memberNote: 'Acceso de miembro',
      },
      stats: {
        members: 'Miembros',
        items: 'Artículos',
        claimed: 'Reservados',
      },
      toolbar: {
        edit: 'Editar',
        delete: 'Eliminar',
      },
      actions: {
        share: 'Compartir',
        leave: 'Salir',
        createList: 'Crear lista',
      },
      members: {
        title: 'Miembros',
        show: 'Mostrar',
        hide: 'Ocultar',
        remove: 'Quitar',
        roles: {
          giver: 'donante',
          recipient: 'destinatario',
          admin: 'admin',
        },
      },
      lists: {
        title: 'Listas',
        emptyTitle: 'Aún no hay listas.',
        emptyBody: 'Crea una para empezar.',
      },
      invite: {
        title: 'Opciones de invitación',
        emailLabel: 'Enviar correo',
        emailPlaceholder: 'nombre@ejemplo.com',
        cancel: 'Cancelar',
        sendEmail: 'Enviar correo',
        sending: 'Enviando…',
        sendCode: 'Enviar código',
        sentTitle: 'Invitación enviada',
        sentBody: 'Hemos enviado tu invitación por correo.',
        missingEmailTitle: 'Falta el correo',
        missingEmailBody: 'Introduce una dirección de correo.',
        sendFailedTitle: 'Error al enviar',
      },
      share: {
        joinWithCode: 'Únete a mi event «{{title}}»: código {{code}}',
      },
      alerts: {
        notAllowedTitle: 'No autorizado',
        onlyAdminDelete: 'Solo un admin puede eliminar este event.',
        deleteTitle: '¿Eliminar el event?',
        deleteBody: 'Esto eliminará todas las listas, artículos y reservas para todos.',
        cancel: 'Cancelar',
        confirmDelete: 'Eliminar',

        loadErrorTitle: 'Error de carga',

        removeMemberTitle: '¿Quitar miembro?',
        removeMemberBody: 'Se le quitará del event y se limpiarán sus reservas.',
        removeFailed: 'Error al quitar',
        alreadyRemoved: 'Ya se quitó',
        memberRemoved: 'Miembro quitado',

        leaveTitle: '¿Salir del event?',
        leaveBody: 'Se te quitará del event y se limpiarán tus reservas.',
        notMember: 'No eres miembro',
        leaveFailed: 'Error al salir',
        leftEvent: 'Has salido del event',
      },
    },

    editEvent: {
      title: 'Editar event',
      labels: {
        title: 'Título',
        date: 'Fecha',
        joinCode: 'Código de invitación',
      },
      placeholders: {
        title: 'p. ej., Cumpleaños de Bob',
        date: 'AAAA-MM-DD',
        selectDate: 'Seleccionar fecha',
      },
      actions: {
        retry: 'Reintentar',
        back: 'Volver',
        copy: 'Copiar',
        save: 'Guardar cambios',
      },
      states: {
        viewOnly: 'Solo lectura (no admin)',
        saving: 'Guardando…',
      },
      messages: {
        signInRequired: 'Se requiere iniciar sesión.',
        notAllowed: 'No autorizado',
        onlyAdmins: 'Solo los admins pueden editar.',
        titleRequired: 'Título requerido',
        enterTitle: 'Introduce un título.',
        eventUnavailable: 'Event no disponible.',
        copied: 'Código copiado',
        copyFailed: 'Error al copiar',
        updated: 'Event actualizado',
        saveFailed: 'Error al guardar',
        failedToLoad: 'No se pudo cargar el event.',
        notFound: 'Event no encontrado o sin acceso.',
      },
    },

    createList: {
      title: 'Crear una lista',
      labels: {
        listName: 'Nombre de la lista',
      },
      placeholders: {
        listName: 'p. ej., Regalos para Bob',
      },
      sections: {
        recipients: {
          title: 'Destinatarios (para quién es la lista)',
          help: 'Toca para elegir uno o varios destinatarios.',
        },
        visibility: {
          title: 'Visibilidad',
          help: 'Elige quién puede ver esta lista.',
        },
        exclusions: {
          title: 'A quién excluir',
          help: 'Quien elijas aquí no verá esta lista (incluso si es destinatario).',
        },
      },
      visibility: {
        public: 'Visible para todos',
        exclude: 'Excluir personas específicas',
      },
      actions: {
        create: 'Crear lista',
      },
      states: {
        creating: 'Creando…',
      },
      toasts: {
        loadError: 'Error de carga',
        notSignedIn: 'No has iniciado sesión',
        listNameRequired: 'Nombre de la lista requerido',
        recipientsRequired: {
          title: 'Destinatarios requeridos',
          body: 'Elige al menos un destinatario.',
        },
        createFailed: {
          title: 'Error al crear',
          noId: 'No se devolvió id de lista.',
        },
        notMember: 'No eres miembro de este event.',
        created: {
          title: 'Lista creada',
          body: 'Tu lista se creó correctamente.',
        },
      },
      user: 'Usuario {{id}}',
    },

    addItem: {
      title: 'Añadir artículo',
      labels: {
        name: 'Nombre del artículo',
        urlOpt: 'URL (opcional)',
        priceOpt: 'Precio (opcional)',
        notesOpt: 'Notas (opcional)',
      },
      placeholders: {
        name: 'p. ej., Auriculares con cancelación de ruido',
        url: 'p. ej., https://ejemplo.com/producto',
        price: 'p. ej., 149,99',
        notes: 'p. ej., Prefiere tipo circumaural',
      },
      actions: {
        add: 'Añadir',
      },
      states: {
        adding: 'Añadiendo…',
      },
      toasts: {
        itemNameRequired: { title: 'Nombre requerido', body: 'Introduce un nombre.' },
        invalidPrice:     { title: 'Precio no válido', body: 'Introduce un número como 19,99' },
        notSignedIn: 'No has iniciado sesión',
        added: 'Artículo añadido',
        addFailed: { title: 'Error al añadir' },
      },
      errors: {
        generic: 'Error',
      },
    },

    listDetail: {
      title: 'Lista',
      actions: {
        addItem: 'Añadir artículo',
        delete: 'Eliminar',
      },
      empty: 'Aún no hay artículos.',
      summary: {
        label: 'Reservados: {{claimed}} · Sin reservar: {{unclaimed}}',
      },
      item: {
        notClaimed: 'Sin reservar todavía',
        claimedByYou: 'Reservado por: Tú',
        claimedByName: 'Reservado por: {{name}}',
        hiddenForRecipients: 'Quién compra permanece oculto para los destinatarios.',
        someone: 'Alguien',
      },
      confirm: {
        deleteItemTitle: '¿Eliminar artículo?',
        deleteItemBody: 'Esto eliminará «{{name}}» y sus reservas.',
        deleteListTitle: '¿Eliminar esta lista?',
        deleteListBody: 'Esto eliminará la lista y todos sus artículos y reservas. No se puede deshacer.',
      },
      errors: {
        generic: 'Error',
        load: 'Ocurrió un problema al cargar la lista.',
        notFound: 'Esta lista no existe o no tienes acceso.',
        notAllowed: 'No autorizado',
        cannotDeleteBody: 'No puedes eliminar este artículo.',
        hasClaimsTitle: 'No se puede eliminar',
        hasClaimsBody: 'Desmarca primero o contacta con un admin/propietario.',
        alreadyGoneTitle: 'Ya no existe',
        alreadyGoneBody: 'Este artículo ya no existe.',
        deleteFailed: 'Error al eliminar',
        directDeleteBlocked: 'Eliminación directa bloqueada',
        goBack: 'Volver',
      },
    },

    allLists: {
      title: 'Todas las listas',
      eventLabel: 'Event: {{title}}',
      event: 'Event',
      empty: 'Aún no hay listas visibles para ti.',
    },

    myClaims: {
      title: 'Mis artículos reservados',
      line: '{{event}} · {{list}}',
      markPurchased: 'Marcar como comprado',
      markNotPurchased: 'Marcar como no comprado',
      empty: 'Todavía no has reservado nada.',
      updateFailed: 'Error al actualizar',
      fallbackItem: 'Artículo',
      fallbackList: 'Lista',
      fallbackEvent: 'Event',
    },

    createEvent: {
      titleLabel: 'Título',
      titlePlaceholder: 'p. ej., Cumpleaños de Bob',
      descriptionLabel: 'Descripción (opcional)',
      descriptionPlaceholder: 'p. ej., Lugar, temática, notas…',
      dateLabel: 'Fecha del event (opcional)',
      datePlaceholder: 'Seleccionar fecha',
      done: 'Listo',
      recursLabel: 'Se repite',
      recurs: { none: 'Ninguna', weekly: 'Semanal', monthly: 'Mensual', yearly: 'Anual' },
      create: 'Crear',
      creating: 'Creando…',
      toastMissingTitleTitle: 'Falta el título',
      toastMissingTitleBody: 'Introduce un título de event.',
      toastCreated: 'Event creado',
      toastCreateFailed: 'Error al crear',
    },

    joinEvent: {
      heading: 'Unirse a un event',
      codeLabel: 'Introduce el código',
      codePlaceholder: 'p. ej., 7G4K-MQ',
      join: 'Unirse',
      joining: 'Uniéndose…',
      alertEnterTitle: 'Introduce un código',
      alertEnterBody: 'Pega el código de unión.',
      alertInvalidTitle: 'Código no válido',
      alertInvalidBody: 'No se encontró ese código.',
      alertFailedTitle: 'Error al unirse',
    },
  },
} as const;

export default es;
