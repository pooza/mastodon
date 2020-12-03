import { connect } from 'react-redux';
import TagSetDropdown from '../components/tagset_dropdown';
import { changeTagSet } from '../../../actions/compose';
import { openModal, closeModal } from '../../../actions/modal';
import { isUserTouching } from '../../../is_mobile';

const mapStateToProps = state => ({
  isModalOpen: state.get('modal').modalType === 'ACTIONS',
  value: '',
});

const mapDispatchToProps = dispatch => ({

  onChange (value) {
    dispatch(changeTagSet(value));
  },

  isUserTouching,
  onModalOpen: props => dispatch(openModal('ACTIONS', props)),
  onModalClose: () => dispatch(closeModal()),

});

export default connect(mapStateToProps, mapDispatchToProps)(TagSetDropdown);
